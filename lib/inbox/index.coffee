express = require 'express'
app = module.exports = express()

app.set 'views', __dirname

#module.exports.model = require './user'

#db = require 'db'
#db.events.on 'start', -> module.exports.model.db db

app.get '/inbox', (req, res) ->
    if not req.session.authed then return res.redirect '/'
    
    view = res.locals
    view.pageTitle = view.user.username + '\'s Inbox'
    res.render 'index'
