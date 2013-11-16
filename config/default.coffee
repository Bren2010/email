fs = require 'fs'

module.exports.sessionSecret = 'your secret here'

module.exports.database = # RethinkDB
    host: 'localhost'
    port: 28015
    db: 'email'

module.exports.https =
    key: fs.readFileSync './test.key', 'utf8'
    cert: fs.readFileSync './test.crt', 'utf8'
    # ca: fs.readFileSync './ca.crt', 'utf8'
    # crl: fs.readFileSync './crl.pem', 'utf8'
    requestCert: false
    rejectUnauthorized: false
