#!/usr/bin/env ruby
require "./" + File.dirname(__FILE__) + '/pwrtls.rb'
if ARGV.length == 1
	kp = PwrTLS.keypair_load(ARGV[0])
	puts PwrTLS.key_fingerprint(kp["pubkey"])
else
	puts "Usage: #{$0} <filename>"
end
