pwrrb: pwrcall and pwrtls for Ruby
==================================

[pwrcall](https://github.com/rep/pwrcall) is an experimental
[remote procedure call system (RPC)](https://en.wikipedia.org/wiki/Remote_procedure_call)
with integrated
[capability-based security](https://en.wikipedia.org/wiki/Capability-based_security),
started by [Mark Schlösser](https://github.com/rep/).
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
* bson, json, yajl-ruby (for message packing)
* [nacl](https://github.com/mogest/nacl) (for hyper security)
* colorize (for increased fancyness)

TODO
----
* pwrcall
    * proxy support
    * pwrcall:// URL parser
* pwrtls
    * verify all crypto boxes and keys
    * read own key from file
    * implement "generate new key and save to file" function
* pwrtools
    * getopt
    * logger
        * prefix all server log output with client number
        * finer debug levels
    * pwrunpackers
        * msgpack
* documentation
