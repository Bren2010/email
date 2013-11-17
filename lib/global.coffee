user = require('user').model

exports.getUser = (req, res, next) ->
    res.locals.session = req.session
    res.locals._csrf = req.csrfToken()
    
    if not req.session.authed or req.path is '/user/logout' then return next()
    
    # Invalidate sessions that are older than 1 day.  (By authenticated time.)
    age = Date.now() - req.session.time
    if age > 86400000 then return res.redirect '/user/logout'
    
    # Load the user object for the following controllers.
    res.locals.user = user.create req.session.uid, null
    res.locals.user.load (ok) ->
        if ok then next() else res.redirect '/user/logout'
