user = require('user').model

exports.getUser = (req, res, next) ->
    res.locals.session = req.session
    
    if not req.session.authed or req.path is '/user/logout' then return next()
    
    age = Date.now() - req.session.time
    if age > 86400000 then return res.redirect '/user/logout'
    
    res.locals.user = user.create req.session.uid, null
    res.locals.user.load (ok) ->
        if ok then next() else res.redirect '/user/logout'
