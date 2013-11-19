express = require 'express'
app = module.exports = express()

app.set 'views', __dirname

config = require 'config'
crypto = require 'crypto'
http = require 'http'
{check} = require 'validator'

#module.exports.model = require './user'

#db = require 'db'
#db.events.on 'start', -> module.exports.model.db db

app.get '/inbox', (req, res) ->
    if not req.session.authed then return res.redirect '/'
    
    view = res.locals
    view.pageTitle = view.user.username + '\'s Inbox'
    
    # Generate a tag that can authenticate us on the stream.
    view.tag = req.session.uid + '.' + Math.floor(Date.now() / 60000)
    
    mac = crypto.createHmac 'sha256', config.sessionSecret
    mac.end view.tag
    view.tag += '.' + mac.read().toString 'base64'
    
    res.render 'index'

module.exports.handler = (socket) ->
    [authed, user] = [false, '']
    
    socket.on 'login', (data) ->
        data = data.split '.'
        time = Math.floor(new Date().getTime() / 60000)
        
        h = crypto.createHmac 'sha256', config.sessionSecret
        h.end data[0] + '.' + data[1]
        
        mac = h.read().toString 'base64'
        
        if data[2] is mac and data[1] - time <= 2 and time >= data[1]
            [authed, user] = [true, data[1]]
    
    socket.on 'pubKey', (address) ->
        try
            check(address).len(6, 64).isEmail()
            [user, domain] = address.split '@'
            
            http.get 'http://' + domain + '/pubKey/' + user, (res) ->
                buff = ''
                res.on 'data', (part) ->
                    buff += part.toString()
                    if buff.length > 1024 then throw 'size'
                
                res.on 'end', -> socket.emit 'pubKey', buff
        
        catch e then socket.emit 'pubKey', false
