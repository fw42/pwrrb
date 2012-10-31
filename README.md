pwrrb: pwrcall and pwrtls for Ruby
==================================

[pwrcall](https://github.com/rep/pwrcall) is an experimental and lightweight
[remote procedure call system (RPC)](https://en.wikipedia.org/wiki/Remote_procedure_call)
with integrated
[capability-based security](https://en.wikipedia.org/wiki/Capability-based_security),
started by [Mark Schloesser](https://github.com/rep/).
[pwrtls](https://github.com/rep/ptls) is an encrypted and authenticated transport layer
between TCP and pwrcall, based on ideas from
[Daniel Bernstein's](http://cr.yp.to/djb.html)
[CurveCP](http://curvecp.org/).

This repository contains my Ruby implementation of pwrcall and pwrtls,
based on EventMachine and Fibers. This code is to be considered
WORK IN PROGRESS and not even close to being finished.

Requirements
------------
You will need at least the following Ruby gems:
* eventmachine (for event magic)
* bson, msgpack, or json and yajl-ruby (for message packing)
* [nacl](https://github.com/mogest/nacl) (for hyper security)
* colorize (for increased fancyness)
* rb-readline (for non-blocking readline and interactive pwrcall shell)

TODO
----
* pwrcall
    * standardized error messages, etc.
    * auto-detect if connection uses pwrtls or not
* pwrsh
    * log messages overwrite prompt when previous command was silent (";" at end or just "\n")
    * pry kills stty return key  
* pwrtls
    * knownhosts/authorizedkeys authentication (on both sides)
    * verify all crypto boxes and keys
    * increment lnonce in keyfile (open, read, write, close; all in getlnonce method)
* pwrtools
    * logger
        * prefix all server log output with client number
        * finer debug levels
* documentation
    * install howto, Gemfile, packaging, etc.
