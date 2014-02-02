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
    
    # Fetch new emails.
    socket.on 'fetch', ->
        module.exports.model.getNew userId, (emails) ->
            socket.emit 'fetch', emails
    
    # Mark an email as read.
    socket.on 'read', (id) ->
        email = module.exports.model.create id, null
        email.load (ok) ->
            if not ok or email.user isnt userId then return
            email.read = true
            email.save (err, out) ->
    
    # Update the old, unprocessed emails, with the new processed ones.
    socket.on 'process', (emails) ->
        console.log emails
        ids = []
        ids.push email.id for email in emails when email.id?
        
        module.exports.model.getAll userId, ids, (emails2) ->
            for i, email of emails2
                for cand in emails when cand.id is email.id
                    emails2[i].from = cand.from
                    emails2[i].subject = cand.subject
                    emails2[i].body = cand.body
                    emails2[i].pubKey = cand.pubKey
            
            module.exports.model.massUpdate emails2, (err, out) ->
                socket.emit 'process'
    
    # Attempt to merge indexes.  This is all translations and adaptations from
    # the caesar library.
    socket.on 'index', (newIds, domain, reps, index, privKey) ->
        if not authed then return
        
        u = user.create userId, null
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
                module.exports.model.getAll userId, newIds, (emails) ->
                    # 1.  Update user's keystore and metadata.
                    console.log domain
                    console.log index.docs
                    console.log reps
                    
                    u.privKey = privKey
                    u.search[domain] = index.docs
                    delete u.search[dn] for dn in reps
                    u._new = true # Forces deletions to hold.
                    
                    # 2.  Mark email as processed.
                    emails[i].processed = true for i of emails
                    
                    indexes = []
                    for key, doc of index.index
                        entry =
                            user: userId
                            domain: domain
                            key: key
                            doc: doc
                        
                        indexes.push search.create null, entry
                    
                    fns = []
                    fns.push u.save.bind u
                    
                    # 3. Insert new indexes.
                    # 4. Delete old indexes.
                    update = (fn) -> module.exports.model.massUpdate emails, fn
                    ins = (fn) -> search.massInsert indexes, fn
                    del = (fn) -> search.massDeleteByDn userId, reps, fn
                    
                    fns.push update.bind this
                    fns.push ins.bind this
                    fns.push del.bind this
                    
                    run = (fn, done) -> fn (err, out) -> done()
                    async.each fns, run, -> socket.emit 'done'
            else
                module.exports.model.getAll userId, index.docs, (emails) ->
                    socket.emit 'index', newIds, reps, emails
