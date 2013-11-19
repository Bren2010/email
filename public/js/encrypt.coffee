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
    pubKey =
        elGamal: elGamal.pub.get()
        ecdsa: ecdsa.pub.get()
    
    pubKey.elGamal.x = sjcl.codec.base64.fromBits pubKey.elGamal.x
    pubKey.elGamal.y = sjcl.codec.base64.fromBits pubKey.elGamal.y
    pubKey.ecdsa.x = sjcl.codec.base64.fromBits pubKey.ecdsa.x
    pubKey.ecdsa.y = sjcl.codec.base64.fromBits pubKey.ecdsa.y
    
    form.pubKey.value = JSON.stringify pubKey
    
    # Serialize the private keys.
    privKey =
        elGamal: sjcl.codec.hex.fromBits elGamal.sec.get()
        ecdsa: sjcl.codec.hex.fromBits ecdsa.sec.get()
    
    form.privKey.value = sjcl.encrypt pass, JSON.stringify privKey
    
    true

window.compose = (form) ->


### Manage server interactions ###
if window.privKey? # This is an inbox page.
    # Load private key into memory.
    privKey = sjcl.decrypt window.localStorage.pass, window.privKey
    privKey = JSON.parse privKey
    
    curve = sjcl.ecc.curves.c256
    privKey.elGamal = new sjcl.bn privKey.elGamal
    privKey.ecdsa = new sjcl.bn privKey.ecdsa
    
    privKey.elGamal = new sjcl.ecc.elGamal.secretKey curve, privKey.elGamal
    privKey.ecdsa = new sjcl.ecc.ecdsa.secretKey curve, privKey.ecdsa
    
    window.socket = io.connect 'http://localhost:3000'
    window.socket.emit 'login', window.tag
