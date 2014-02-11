Encrypted Email
===============

Prototype--not really intended to be used for real stuff.  I wanted to see if putting SSE (Searchable Symmetric Encryption) in a web browser was actually feasible, because if it was, it would give cryptographically blinded services 
a wider range of capabilities.

I think works pretty well.


Setup
-----
1.  Install RethinkDB
    - Database/table setup like this:  (The database and location of the RDB sever can be configured.)
      - `email`
        - `emails`
        - `users`
        - `index`  (Secondary indexes `domain` and `key`)
2.  Install Node.js and coffeescript.
3.  Install modules with `npm install` (run in work directory)
4.  Start with `npm start`


Other Information
-----------------
1.  Email addresses need to include ports.  For example:  username@localhost:3000
