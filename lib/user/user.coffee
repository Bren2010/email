{BaseModel} = require 'baseModel'
{check} = require 'validator'

bcrypt = require 'bcrypt'
async = require 'async'

# Prepares a database table for this model to use.
#
# @param class  db  The database connection to use.
exports.db = (db) -> 
    module.d = db.r
    module.r = db.r.table 'users'
    module.c = db.conn

# Describes the data and operations of a user.
class User extends BaseModel
    constructor: (@id, entry) ->
        @username = entry?.username ? "Guest"
        @password = entry?.password ? null
        @pubKey   = entry?.pubKey ? null
        @privKey  = entry?.privKey ? null
        @search   = entry?.search ? {}
    
    # Authenticates a user's account.
    #
    # @param string pass The password to check.
    #
    # @return bool Whether or not the user was successfully authed.
    authenticate: (pass, fn) ->
        realPass = if @_password? then @_password else @password
        bcrypt.compare pass, realPass, fn
    
    validate: ->
        check(@username, 'username').notEmpty().not('Guest').len(4, 16)
        check(@password, 'password').notEmpty()
        check(@pubKey, 'key').notEmpty()
        check(@privKey, 'key').notEmpty()
    
    goodPassword: (password) ->
        if password.length is 0 then return false # No empty passwords.
        
        true
    
    setPassword: (password, fn) ->
        if not @goodPassword password then return fn()
        bcrypt.hash password, 10, (err, hashed) =>
            @password = hashed if not err?
            fn()
    
    # @see BaseModel::humanize()
    humanize: ->
        super ['password']
        
        @__defineGetter__ 'password', () -> null
        @__defineSetter__ 'password', (password) -> @_password = password
    
    # @see BaseModel::{dehumanize(),...,del()}
    dehumanize: -> super ['password']
    
    load: (fn) -> super 'user', fn, module
    save: (fn) -> super fn, module
    del: (fn) -> super fn, module


# Creates a new user object.
#
# @param string/null  id     The user's id.  (Null for a new entry.)
# @param object/null  entry  The user's data.  (Null for existing.)
#
# @return User The user described.
exports.create = (id, entry) -> new User id, entry

# Gets a user by their username.
#
# @param string  username    The user's username.
# @param callback  fn(User)  Called when the user is loaded.
#
# @return User The user described.
exports.getByUsername = (username, fn) ->
    module.r.filter('username' : username).run module.c, (err, cur) ->
        out = null
        test = -> cur.hasNext()
        processEntry = (done) ->
            cur.next (err, entry) ->
                id = entry.id
                delete entry.id
                
                entry = exports.create id, entry
                entry.humanize()
                out = entry
                done()
        
        async.whilst test, processEntry, -> fn out
