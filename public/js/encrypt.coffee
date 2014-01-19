decryptEmail = (privKey, email) ->
    try
        email.from = sjcl.decrypt privKey, email.from
        email.subject = sjcl.decrypt privKey, email.subject
        email.body = sjcl.decrypt privKey, email.body
        email.pubKey = JSON.parse sjcl.decrypt privKey, email.pubKey
    catch e then return [{}, 'Bad']
    
    pubKey = sjcl.ecc.deserialize email.pubKey.ecdsa
    corpus = subject: email.subject, body: email.body
    corpus = sjcl.hash.sha256.hash JSON.stringify corpus
    
    try
        ok = pubKey.verify corpus, sjcl.codec.base64.toBits email.signature
        return [email, null]
    catch e
        email.subject += '  (Modified Contents!)'
        return [email, 'Bad']


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
        
        pub.elGamal = sjcl.ecc.deserialize pub.elGamal
        
        # pubKey.ecdsa = ... Not needed for this.
        
        # Encrypt form fields.
        corpus = subject: form.subject.value, body: form.body.value
        corpus = sjcl.hash.sha256.hash JSON.stringify corpus
        corpus = window.privKey.ecdsa.sign corpus, 10
        corpus = sjcl.codec.base64.fromBits corpus
        
        form.from.value = sjcl.encrypt pub.elGamal, window.from
        form.subject.value = sjcl.encrypt pub.elGamal, form.subject.value
        form.body.value = sjcl.encrypt pub.elGamal, form.body.value
        form.signature.value = corpus
        form.pubKey.value = sjcl.encrypt pub.elGamal, window.pubKey
        
        true
    catch e
        alert e
        false

window.view = (email) ->
    email = JSON.parse unescape email
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
        
        email = emails[i]
        [email, err] = decryptEmail window.privKey.elGamal, email
        if err? then c = 'warning'
        
        c = if err? then 'danger' else if not email.read then 'warning' else ''
        cb = 'window.view(\'' + escape(JSON.stringify(email)) + '\')'
        tr = '<tr id="' + email.id + '" onclick="' + cb + '" '
        tr = tr + 'style="display: none" class="' + c + '">'
        tr = tr + '<td id="from-' + email.id + '">' + email.from + '</td>'
        tr = tr + '<td id="subj-' + email.id + '"></td>'
        tr = tr + '<td>' + email.date + '</td></tr>'
        
        $('#emails tr:last').after tr
        $('#from-' + email.id).text email.from
        $('#subj-' + email.id).text email.subject
        
        $('#' + email.id).show 1000, -> loadEmail i + 1
    
    if emails.length isnt 0 then $('#emails').show 'fast', -> loadEmail 0
    else $('#error').show 'fast', -> $('#loading').hide 'fast'

window.socket.on 'index', (newId, reps, emails) ->
    [max, indexes] = [0, []]
    
    # Calculate index.
    for email in emails
        index = {}
        [email, err] = decryptEmail window.privKey.elGamal, email
        if err? then continue
        
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

