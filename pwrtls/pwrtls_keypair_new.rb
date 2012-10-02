#!/usr/bin/env ruby
require "./" + File.dirname(__FILE__) + '/pwrtls.rb'
if ARGV.length == 1
	PwrTLS.keypair_init(ARGV[0])
else
	puts "Usage: #{$0} <filename>"
end
