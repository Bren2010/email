fs = require 'fs'

module.exports.domain = 'email.com'
module.exports.port = 3000
module.exports.sessionSecret = 'your secret here'

module.exports.database = # RethinkDB
    host: 'localhost'
    port: 28015
    db: 'email'

module.exports.cache =
    caching: false
    host: '127.0.0.1'
    port: 6379
    opts: null
