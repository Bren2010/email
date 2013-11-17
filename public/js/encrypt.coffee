window.encrypt = (form) ->
    inputs = form.getElementsByTagName 'input'
    for i in [0...inputs.length]
        if inputs[i].type is 'password' # Passwords need to be hashed.
            sum = sjcl.codec.hex.fromBits sjcl.hash.sha256.hash inputs[i].value
            inputs[i].value = sum
