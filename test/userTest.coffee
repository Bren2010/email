assert = require 'assert'
crypto = require 'crypto'

user = require('user').model
db = require 'db'

id = null
entry = null
idealEntry =
    username: 'TempUser'
    password: 'test'

newUsername = 'TempUser2'
badUsername = ''

describe 'Users', ->
    describe 'Model', ->
        it 'should connect to the database', (done) ->
            db.events.once 'start', ->
                db.cache = null
                done()
            
            db.start()
        
        it 'should create a new user', (done) ->
            entry = user.create null, idealEntry
            
            entry.setPassword idealEntry.password, ->
                # Never do this, but here is how you get a user's password.
                entry.dehumanize()
                idealEntry.password = entry.password
                
                entry.save (out, errs) ->
                    assert.equal out.inserted, 1
                    assert.equal out.errors, 0
                    assert.equal out.generated_keys.length, 1
                    assert.equal errs, null
                    
                    id = out.generated_keys[0]
                    
                    done()
        
        it 'should find a user', (done) ->
            assert.notEqual id, null
            
            entry = user.create id, null
            entry.load (ok) ->
                assert.equal ok, true
                
                cmp = (key) =>
                    if typeof idealEntry[key] is 'object' then return
                    assert.equal idealEntry[key], entry[key]
                
                cmp key for key in Object.keys idealEntry
                
                done()
        
        it 'should update a user', (done) ->
            assert.notEqual id, null
            assert.equal entry?, true
            
            entry.username = newUsername
            entry.save (out, errs) ->
                assert.equal out.replaced, 1
                assert.equal out.errors, 0
                assert.equal out.generated_keys, null
                assert.equal errs, null
                
                done()
        
        it 'should fail to update a user', (done) ->
            assert.notEqual id, null
            assert.equal entry?, true
            
            entry.username = badUsername
            entry.save (out, errs) ->
                assert.equal out, null
                assert.equal errs.username, true
                
                done()
        
        it 'should humanize the user', () ->
            assert.equal entry?, true
            
            entry.humanize()
            assert.equal entry.password, null
        
        it 'should dehumanize the user', () ->
            assert.equal entry?, true
            
            entry.dehumanize()
            assert.notEqual entry.password, null
        
        it 'should successfully authenticate the user', (done) ->
            entry.authenticate 'test', (err, authed) ->
                assert.equal authed, true
                done()
        
        it 'should fail to authenticate the user', (done) ->
            entry.authenticate '12345', (err, authed) ->
                assert.equal authed, false
                done()
        
        it 'should get a user by their username', (done) ->
            user.getByUsername idealEntry.username, (user) ->
                assert.equal typeof user, 'object'
                
                done()
        
        it 'should fail to find a user', (done) ->
            entry = user.create 'nonexistent-key', null
            entry.load (ok) ->
                assert.equal ok, false
                
                done()
        
        it 'should delete a user', (done) ->
            assert.notEqual id, null
            
            entry = user.create id, null
            entry.del (out) ->
                assert.notEqual out.deleted, 0
                
                done()
        
        it 'should fail to delete a user', (done) ->
            entry = user.create 'nonexistent-key', null
            entry.del (out) ->
                assert.equal out.deleted, 0
                assert.equal out.skipped, 1
                
                done()
        
        it 'should close the db connection', () -> db.close()
