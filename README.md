pwrcall and pwrtls
==================

TODO
----
* clean up everything, clean up API, ...
* pwrcall
  * SSL support, move SSL code to pwrtls.rb
  * proxy support
* pwrtls
  * server side code
  * verify all crypto boxes and keys
  * read own key from file
  * implement "generate new key and save to file" function
* psk
  * fix nonce stuff
* pwrtools
  * getopt
  * logger
    * prefix all server log output with client number
    * finer debug levels
