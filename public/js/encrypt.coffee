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
        @processed = email?.processed ? false
    
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
            @_decrypted.pubKey = pubKey
            
            pubKey.elGamal = pubKey.elGamal.serialize()
            pubKey.ecdsa = pubKey.ecdsa.serialize()
            pubKey = JSON.stringify pubKey
            
            @_pubKey = sjcl.encrypt @_key, pubKey
        
    
    dehumanize: -> super ['from', 'subject', 'body', 'pubKey']

flashError = ->
    $('#error').show 'slow', ->
        hide = -> $('#error').hide 'slow'
        setTimeout hide, 3000

toggleLoading = -> $('#loading').toggle 'slow'

mergeEmails = (emails) ->
    [max, indexes] = [0, []]
    
    # Calculate index.
    for email in emails
        index = {}
        
        try
            if email.processed
                email = new Email email.id, email, window.dataKey
            else
                email = new Email email.id, email, window.privKey.elGamal
            
            email.humanize()
            
            if not email.processed then email.verify()
            
            corpus = email.from + ' ' + email.subject + ' ' + email.body
            if corpus.length > max then max = corpus.length
            
            tokens = sjcl.searchable.tokenize corpus
            index[token] = email.id for token in tokens
            
            indexes.push index
        catch then continue
    
    out = sjcl.searchable.secureIndex window.searchKeys, max, indexes...
    
    # Re-encrypt keystore.
    key =
        search: window.searchKeys
        data: window.dataKey
        email:
            elGamal: window.privKey.elGamal.serialize()
            ecdsa: window.privKey.ecdsa.serialize()
    
    key = sjcl.encrypt window.localStorage.pass, JSON.stringify key
    [out, key]

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
    privKey.data = sjcl.codec.base64.fromBits sjcl.random.randomWords 8, 10
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
        
        # Decode our public key.
        window.pubKey = JSON.parse window.pubKey
        window.pubKey.elGamal = sjcl.ecc.deserialize window.pubKey.elGamal
        window.pubKey.ecdsa = sjcl.ecc.deserialize window.pubKey.ecdsa
        
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
    
    if not email.read
        document.getElementById(email.id).className = ''
        window.socket.emit 'read', email.id

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

window.fetch = ->
    toggleLoading()
    
    window.socket.emit 'fetch'
    window.socket.on 'fetch', (emails) ->
        if emails.length is 0
            toggleLoading()
            flashError()
            return
        
        newIds = []
        newIds.push email.id for email in emails
        
        [out, key] = mergeEmails emails
        window.socket.emit 'index', newIds, out.newDomain, [], out.index, key
        window.socket.once 'done', ->
            # Re-encrypt all of the emails.
            out = []
            for email in emails
                email = new Email email.id, email, window.privKey.elGamal
                email.humanize()
                
                try email.verify()
                catch err then continue
                
                email2 = new Email email.id, null, window.dataKey
                email2.humanize()
                
                email2.from = email.from
                email2.subject = email.subject
                email2.body = email.body
                email2.pubKey = email.pubKey
                
                email2.dehumanize()
                
                email3 =
                    id: email.id
                    date: email.date
                    from: email2.from
                    subject: email2.subject
                    body: email2.body
                    pubKey: email2.pubKey
                
                out.push email3
            
            # Submit, wait for the confirmation, and refresh the page.
            window.socket.emit 'process', out
            window.socket.once 'process', -> window.location = '/inbox'
    
    false

window.page = (i) ->
    $('#emails tbody').html '<tr></tr>'
    $('#pagination').html '<li class="disabled"><a href="#">&laquo;</a></li>'
    
    window.socket.emit 'page', i

if window.privKey? # This is an inbox page.
    # Load private key into memory.
    privKey = JSON.parse sjcl.decrypt window.localStorage.pass, window.privKey
    window.searchKeys = privKey.search
    window.dataKey = privKey.data
    privKey = privKey.email
    
    privKey.elGamal = sjcl.ecc.deserialize privKey.elGamal
    privKey.ecdsa = sjcl.ecc.deserialize privKey.ecdsa
    window.privKey = privKey
    
    window.socket = io.connect 'http://localhost:3000'
    window.socket.emit 'login', window.tag
    window.socket.on 'authed', -> window.socket.emit 'page', 1

window.socket.on 'page', (p, emails, pages) ->
    loadEmail = (i) ->
        if not emails[i]? then return
        
        email = new Email emails[i].id, emails[i], window.dataKey
        email.humanize()
        window.cache[email.id] = email
        
        c = if not email.read then 'warning' else ''
        cb = 'window.view(\'' + email.id + '\')'
        tr = '<tr id="' + email.id + '" onclick="' + cb + '" '
        tr = tr + 'style="display: none" class="' + c + '">'
        tr = tr + '<td id="from-' + email.id + '"></td>'
        tr = tr + '<td id="subj-' + email.id + '"></td>'
        tr = tr + '<td id="date-' + email.id + '"></td></tr>'
        
        $('#emails tr:last').after tr
        
        try
            $('#from-' + email.id).text email.from
            $('#subj-' + email.id).text email.subject
            $('#date-' + email.id).text email.date
        catch err then alert 'Modified contents.'
        
        $('#' + email.id).show 100, -> loadEmail i + 1
    
    if emails.length isnt 0
        $('#emails').show 'fast', -> loadEmail 0
        
        i = 1
        until i > pages
            c = if i is p then 'disabled' else ''
            li = '<li class="' + c + '"><a href="#" onclick="window.page(' + i +
                ')">' + i + '</a></li>'
            
            $('#pagination li:last').after li
            ++i
        
        last = '<li class="disabled"><a href="#">&raquo;</a></li>'
        $('#pagination li:last').after last
        
    else flashError()

window.socket.on 'index', (newIds, reps, emails) ->
    [out, key] = mergeEmails emails
    window.socket.emit 'index', newIds, out.newDomain, reps, out.index, key
