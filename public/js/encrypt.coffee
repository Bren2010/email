class BaseModel # Stolen from the backend.  Docs stripped.
    humanize: (keys) ->
        swap = (key) => this['_' + key] = this[key]
        swap key for key in keys
    
    dehumanize: (keys) ->
        swap = (key) =>
            if not this['_' + key]? then return
            
            delete this[key]
            this[key] = this['_' + key]
            delete this['_' + key]
        
        swap key for key in keys

# Email wrapper.  Enables lazy cryptography.
class Email extends BaseModel
    constructor: (@id, email, @_key) -> # @_key -> An ElGamal key.  Pub or priv.
        @user = email?.user ? null
        @date = email?.date ? null
        @from = email?.from ? null
        @subject = email?.subject ? null
        @body = email?.body ? null
        @signature = email?.signature ? null
        @pubKey = email?.pubKey ? null
        @read = email?.read ? false
    
    sign: (signingKey) -> # Must be humanized.
        corpus = subject: @_subject, body: @_body
        corpus = sjcl.hash.sha256.hash JSON.stringify corpus
        @signature = signingKey.sign corpus, 10
        @signature = sjcl.codec.base64.fromBits @signature
    
    verify: -> # Must be humanized.
        corpus = subject: @_subject, body: @_body
        corpus = sjcl.hash.sha256.hash JSON.stringify corpus
        ok = @pubKey.ecdsa.verify corpus, sjcl.codec.base64.toBits @signature
        
        ok
    
    humanize: ->
        super ['from', 'subject', 'body', 'pubKey']
        @_decrypted =
            from: null
            subject: null
            body: null
            pubKey: null
        
        @__defineGetter__ 'from', ->
            if not @_decrypted.from?
                @_decrypted.from = sjcl.decrypt @_key, @_from
            
            @_decrypted.from
        
        @__defineSetter__ 'from', (from) ->
            @_decrypted.from = from
            @_from = sjcl.encrypt @_key, from
        
        @__defineGetter__ 'subject', ->
            if not @_decrypted.subject?
                @_decrypted.subject = sjcl.decrypt @_key, @_subject
            
            @_decrypted.subject 
        
        @__defineSetter__ 'subject', (subject) ->
            @_decrypted.subject = subject
            @_subject = sjcl.encrypt @_key, subject
        
        @__defineGetter__ 'body', ->
            if not @_decrypted.body?
                @_decrypted.body = sjcl.decrypt @_key, @_body
            
            @_decrypted.body
        
        @__defineSetter__ 'body', (body) ->
            @_decrypted.body = body
            @_body = sjcl.encrypt @_key, body
        
        @__defineGetter__ 'pubKey', ->
            if not @_decrypted.pubKey?
                pub = JSON.parse sjcl.decrypt @_key, @_pubKey
                pub.elGamal = sjcl.ecc.deserialize pub.elGamal
                pub.ecdsa = sjcl.ecc.deserialize pub.ecdsa
                
                @_decrypted.pubKey = pub
            
            @_decrypted.pubKey
        
        @__defineSetter__ 'pubKey', (pubKey) ->
            pubKey = JSON.stringify pubKey if not typeof pubKey is 'string'
            @_decrypted.pubKey = pubKey
            @_pubKey = sjcl.encrypt @_key, pubKey
        
    
    dehumanize: -> super ['from', 'subject', 'body', 'pubKey']

### Functions to secure forms. ###
window.signin = (form) ->
    # Hash the password.
    pass = form.pass.value
    window.localStorage.pass = pass
    form.pass.value = sjcl.codec.hex.fromBits sjcl.hash.sha256.hash pass
    
    true

window.register = (form) ->
    # Hash the password.
    pass = form.pass.value
    window.localStorage.pass = pass
    form.pass.value = sjcl.codec.hex.fromBits sjcl.hash.sha256.hash pass
    
    # Generate keypairs.
    elGamal = sjcl.ecc.elGamal.generateKeys 256, 10
    ecdsa = sjcl.ecc.ecdsa.generateKeys 256, 10
    
    # Serialize the public keys.
    pubKey = elGamal: elGamal.pub.serialize(), ecdsa: ecdsa.pub.serialize()
    form.pubKey.value = JSON.stringify pubKey
    
    # Serialize the private keys.
    privKey = elGamal: elGamal.sec.serialize(), ecdsa: ecdsa.sec.serialize()
    privKey = email: privKey, search: {}
    form.privKey.value = sjcl.encrypt pass, JSON.stringify privKey
    
    true

window.changePassword = (form) ->
    # Decrypt the private key.
    privKey = sjcl.decrypt window.localStorage.pass, form.privKey.value
    
    # Hash the password.
    pass = form.pass.value
    window.localStorage.pass = pass
    form.pass.value = sjcl.codec.hex.fromBits sjcl.hash.sha256.hash pass
    
    # Encrypt the private key.
    form.privKey.value = sjcl.encrypt window.localStorage.pass, privKey
    
    true

window.compose = (form) ->
    try
        if not window.toPubKey? then throw 'Invalid destination address.'
        
        # Decode the other person's public key.
        pub = JSON.parse window.toPubKey
        curve = sjcl.ecc.curves.c256
        
        encryptionKey = sjcl.ecc.deserialize pub.elGamal
        # pubKey.ecdsa = ... Not needed for this.
        
        email = new Email null, null, encryptionKey
        email.humanize()
        
        email.from = window.from
        email.subject = form.subject.value
        email.body = form.body.value
        email.pubKey = window.pubKey
        email.sign window.privKey.ecdsa
        
        email.dehumanize()
        
        form.from.value = email.from
        form.subject.value = email.subject
        form.body.value = email.body
        form.signature.value = email.signature
        form.pubKey.value = email.pubKey
        
        true
    catch e
        alert e
        false

window.view = (id) ->
    email = window.cache[id]
    
    footer = 'From ' + email.from + ' on ' + email.date
    
    $('#view-subj').text email.subject
    $('#view-body').text email.body
    $('#view-footer').text footer
    
    $('#view').modal()
    
    if not email.read # Set as read and index.
        document.getElementById(email.id).className = ''
        
        corpus = email.from + ' ' + email.subject + ' ' + email.body
        max = corpus.length
        tokens = sjcl.searchable.tokenize corpus
        o = sjcl.searchable.secureIndex window.searchKeys, max, tokens
        
        # Fix index.
        o.index.docs = [email.id]
        o.index.index[k] = email.id for k, v of o.index.index when v is o.newId
        
        # Re-encrypt keystore.
        key =
            search: window.searchKeys
            email:
                elGamal: window.privKey.elGamal.serialize()
                ecdsa: window.privKey.ecdsa.serialize()
        
        key = sjcl.encrypt window.localStorage.pass, JSON.stringify key
        window.socket.emit 'index', email.id, o.newDomain, [], o.index, key


### Manage server interactions ###
window.getPubKey = (input) ->
    if not window.socket? then return alert 'Could not contact server!'
    if window.to is input.value then return
    
    [window.to, window.toPubKey] = [input.value, null]
    statusIcon = document.getElementById 'to-status-icon'
    statusIcon.className = 'glyphicon glyphicon-refresh'
    
    window.socket.emit 'pubKey', input.value
    window.socket.once 'pubKey', (pubKey) ->
        if pubKey isnt false
            statusIcon.className = 'glyphicon glyphicon-ok'
            window.toPubKey = pubKey
        else statusIcon.className = 'glyphicon glyphicon-remove'

if window.privKey? # This is an inbox page.
    # Load private key into memory.
    privKey = JSON.parse sjcl.decrypt window.localStorage.pass, window.privKey
    window.searchKeys = privKey.search
    privKey = privKey.email
    
    privKey.elGamal = sjcl.ecc.deserialize privKey.elGamal
    privKey.ecdsa = sjcl.ecc.deserialize privKey.ecdsa
    window.privKey = privKey
    
    window.socket = io.connect 'http://localhost:3000'
    window.socket.emit 'login', window.tag
    window.socket.on 'authed', -> window.socket.emit 'page', 1

window.socket.on 'page', (emails) ->
    loadEmail = (i) ->
        if not emails[i]? then return $('#loading').hide 'fast'
        
        email = new Email emails[i].id, emails[i], window.privKey.elGamal
        email.humanize()
        window.cache[email.id] = email
        
        try email.verify()
        catch err then err = true
        
        c = if err? then 'danger' else if not email.read then 'warning' else ''
        cb = 'window.view(\'' + email.id + '\')'
        tr = '<tr id="' + email.id + '" onclick="' + cb + '" '
        tr = tr + 'style="display: none" class="' + c + '">'
        tr = tr + '<td id="from-' + email.id + '"></td>'
        tr = tr + '<td id="subj-' + email.id + '"></td>'
        tr = tr + '<td id="date-' + email.id + '"></td></tr>'
        
        $('#emails tr:last').after tr
        $('#from-' + email.id).text email.from
        $('#subj-' + email.id).text email.subject
        $('#date-' + email.id).text email.date
        
        $('#' + email.id).show 1000, -> loadEmail i + 1
    
    if emails.length isnt 0 then $('#emails').show 'fast', -> loadEmail 0
    else $('#error').show 'fast', -> $('#loading').hide 'fast'

window.socket.on 'index', (newId, reps, emails) ->
    [max, indexes] = [0, []]
    
    # Calculate index.
    for email in emails
        index = {}
        email = new Email email.id, email, window.privKey.elGamal
        
        try email.verify()
        catch err then continue
        
        corpus = email.from + ' ' + email.subject + ' ' + email.body
        if corpus.length > max then max = corpus.length
        
        tokens = sjcl.searchable.tokenize corpus
        index[token] = email.id for token in tokens
        
        indexes.push index
    
    out = sjcl.searchable.secureIndex window.searchKeys, max, indexes...
    
    # Re-encrypt keystore.
    key =
        search: window.searchKeys
        email:
            elGamal: window.privKey.elGamal.serialize()
            ecdsa: window.privKey.ecdsa.serialize()
    
    key = sjcl.encrypt window.localStorage.pass, JSON.stringify key
    window.socket.emit 'index', newId, out.newDomain, reps, out.index, key

