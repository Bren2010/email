express = require 'express'
app = module.exports = express()

app.set 'views', __dirname + '/..'

app.get '/', (req, res) ->
    res.redirect if req.session.authed then '/inbox' else '/user/login'

