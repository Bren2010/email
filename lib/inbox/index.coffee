express = require 'express'
app = module.exports = express()

app.set 'views', __dirname

async = require 'async'
config = require 'config'
crypto = require 'crypto'
http = require 'http'
url = require 'url'
querystring = require 'querystring'
{check} = require 'validator'
user = require('user').model
search = require 'search'

module.exports.model = require './email'

db = require 'db'
db.events.on 'start', ->
    module.exports.model.db db
    search.db db

app.get '/inbox', (req, res) ->
    if not req.session.authed then return res.redirect '/'
    
    view = res.locals
    view.pageTitle = view.user.username + '\'s Inbox'
    view.domain = config.domain
    
    # Generate a tag that can authenticate us on the stream.
    view.tag = req.session.uid + '.' + Math.floor(Date.now() / 60000)
    
    mac = crypto.createHmac 'sha256', config.sessionSecret
    mac.end view.tag
    view.tag += '.' + mac.read().toString 'base64'
    
    res.render 'index'

app.post '/inbox/send', (req, res) ->
    if not req.session.authed then return res.redirect '/'
    
    view = res.locals
    email =
        to: req.param 'to'
        from: req.param 'from'
        subject: req.param 'subject'
        body: req.param 'body'
        signature: req.param 'signature'
        pubKey: req.param 'pubKey'
    
    try
        # Verify input.
        [username, domain] = email.to.split '@'
        if not username? or not domain? then throw 'bad'
        
        check(username, 'user').isAlphanumeric()
        check(domain, 'domain').isUrl()
        check(email.subject, 'subject').len(64, 1024)
        check(email.body, 'body').len(64, 10240)
        check(email.signature, 'signature').len(32, 256)
        check(email.pubKey, 'pubKey').len(10, 1024)
        
        # Send email.
        delete email.to
        email = querystring.stringify email
        opts = url.parse 'http://' + domain + '/inbox/send/' + username
        opts.method = 'POST'
        opts.headers =
            'Content-Type' : 'application/x-www-form-urlencoded'
            'Content-Length' : Buffer.byteLength email
        
        conn = http.request opts, (out) =>
            out.on 'data', (out) ->
            out.on 'end', => res.redirect '/'
        
        conn.on 'error', (err) -> console.error 'app:inbox/send:  ', err
        conn.write email
        conn.end()
    catch e then res.send e.toString()

app.post '/inbox/send/:user', (req, res) ->
    username = req.param 'user'
    from = req.param 'from'
    subject = req.param 'subject'
    body = req.param 'body'
    sig = req.param 'signature'
    pubKey = req.param 'pubKey'
    
    if not username? or not from? then return res.send 'missing data'
    if not subject? or not body? then return res.send 'missing data'
    if not sig? or not pubKey? then return res.send 'missing data'
    
    user.getByUsername username, (u) ->
        if not u? then return res.send 'user not known'
        
        email =
            user: u.id
            from: from
            subject: subject
            body: body
            signature: sig
            pubKey: pubKey
        
        email = module.exports.model.create null, email
        email.save (out, err) ->
            if err? then console.error 'app:inbox/send/:user:  ', out, err
            if err? then res.send 'error' else res.send 'ok'

module.exports.handler = (socket) ->
    [authed, userId] = [false, '']
    
    # Authenticate a user with their tag.
    socket.on 'login', (data) ->
        data = data.split '.'
        time = Math.floor(new Date().getTime() / 60000)
        
        h = crypto.createHmac 'sha256', config.sessionSecret
        h.end data[0] + '.' + data[1]
        
        mac = h.read().toString 'base64'
        
        if data[2] is mac and data[1] - time <= 2 and time >= data[1]
            [authed, userId] = [true, data[0]]
            socket.emit 'authed'
    
    # Get a page of emails.
    socket.on 'page', (p) ->
        if not authed then return
        
        module.exports.model.getPage userId, p, (emails) ->
            socket.emit 'page', emails
    
    # Get the public key of a foreign user.
    socket.on 'pubKey', (address) ->
        if not authed then return
        
        try
            [username, domain] = address.split '@'
            if not username? or not domain? then throw 'bad'
            
            check(username, 'user').isAlphanumeric()
            check(domain, 'domain').isUrl()
            
            conn = http.get 'http://' + domain + '/pubKey/' + username, (res) ->
                buff = ''
                res.on 'data', (part) ->
                    buff += part.toString()
                    if buff.length > 1024 then throw 'size'
                
                res.on 'end', -> socket.emit 'pubKey', buff
            
            conn.on 'error', (err) ->
                console.error 'socket:pubKey:conn:  ', err
                socket.emit 'pubKey', false
            
        catch e
            console.error 'socket:pubKey:  ', e.toString()
            socket.emit 'pubKey', false
    
    # Attempt to merge indexes.  This is all translations and adaptations from
    # the caesar library.
    socket.on 'index', (newId, domain, reps, index, privKey) ->
        u = user.create userId
        u.load (ok) ->
            checkIndex = (archive, reps, index) ->
                for dn, docs of archive when -1 is reps.indexOf dn
                    if docs.length <= index.docs.length then return [dn, docs]
                
                true
            
            altered = false
            until true is out = checkIndex u.search, reps, index
                reps.push out[0]
                index.docs.push out[1]...
                altered = true
            
            if not altered
                email = module.exports.model.create newId, null
                email.load (ok) ->
                    if not ok then return console.error 'socket:index:'
                    
                    # 1.  Update user's keystore and meta data.
                    u.privKey = privKey
                    u.search[domain] = index.docs
                    delete u.search[dn] for dn in reps
                    u._new = true # Forces deletions to hold.
                    email.read = true # 2.  Mark email as read.
                    
                    
                    models = [u, email]
                    for key, doc of index.index
                        entry =
                            user: userId
                            domain: domain
                            key: key
                            doc: doc
                        
                        models.push search.create null, entry
                    
                    getModels = (dn, done) =>
                        search.getByDomain userId, dn, (indexes) =>
                            models.push index for index in indexes
                            done()
                    
                    async.each reps, getModels, =>
                        save = (model, done) -> model.save (ok) -> done()
                        async.each models, save, -> socket.emit 'done'
            else
                module.exports.model.getAll userId, index.docs, (emails) ->
                    socket.emit 'index', newId, reps, emails
