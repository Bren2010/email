express = require 'express'
app = module.exports = express()

app.set 'views', __dirname

module.exports.model = require './user'

db = require 'db'
db.events.on 'start', -> module.exports.model.db db

login = (session, user) ->
    session.uid = user.id
    session.authed = true
    session.time = Date.now()

app.get '/pubKey/:user', (req, res) ->
    module.exports.model.getByUsername req.param('user'), (user) ->
        if user? then return res.send user.pubKey else res.send 'bad'

app.get '/user/login', (req, res) ->
    res.locals.pageTitle = 'Login'
    res.render 'login'

app.post '/user/login', (req, res) ->
    res.locals.pageTitle = 'Login'
    [user, pass] = [req.param('user'), req.param('pass')]
    
    auth = (user, pass, done) ->
        module.exports.model.getByUsername user, (user) ->
            if user is null then return done false, null
            user.authenticate pass, (err, res) ->
                if err? then done false, null else done res, user
    
    auth user, pass, (ok, user) ->
        if ok
            login req.session, user
            res.redirect '/'
        else
            res.locals.err = login: true
            res.render 'login'

app.get '/user/register', (req, res) ->
    res.locals.pageTitle = 'Register'
    res.render 'register'

app.post '/user/register', (req, res) ->
    res.locals.pageTitle = 'Register'
    
    # Basic user entry.
    entry =
        username: req.param 'user'
        pubKey: req.param 'pubKey'
        privKey: req.param 'privKey'
    
    console.log entry
    
    # Called to route the user once all of the work is done.
    fn = (err, user) ->
        if err isnt null
            res.locals.err = err
            res.locals.username = req.param 'user'
            res.render 'register'
        else
            login req.session, user
            res.redirect '/'
    
    if not entry.username? then return fn username: true
    
    module.exports.model.getByUsername req.param('user'), (user) ->
        # Prevent duplicate users.
        if user isnt null then return fn taken: true
        
        # Create user entry.
        entry = module.exports.model.create null, entry
        entry.humanize()
        
        # Set extra data.
        entry.setPassword req.param('pass'), -> # Hashes it.
            # Save the user to the db or return errors.
            entry.save (out, err) -> fn err, entry

app.get '/user/settings', (req, res) ->
    if not req.session.authed then return res.redirect '/'
    res.locals.pageTitle = 'Settings'
    res.render 'settings'

app.post '/user/settings', (req, res) ->
    # Aliasing and login check.
    [session, view, user] = [req.session, res.locals, res.locals.user]
    if not session.authed then return res.redirect '/'
    view.pageTitle = 'Settings'
    
    # Handle password and private key.
    user.privKey = req.param 'privKey'
    user.setPassword req.param('pass'), ->
        # Save and reload to get the latest user object.
        user.save (out, err) ->
            view.err = err
            
            user = module.exports.model.create session.uid, null
            user.load (ok) ->
                view.ok = ok
                res.render 'settings'

app.get '/user/logout', (req, res) ->
    delete req.session.uid
    delete req.session.authed
    delete req.session.time
    
    res.redirect 'back'
