#!/usr/bin/env ruby
require File.expand_path("../pwrtls.rb", __FILE__)

if ARGV.length == 1
	kp = PwrTLS.keypair_load(ARGV[0])
	puts PwrTLS.key_fingerprint(kp["pubkey"])
else
	puts "Usage: #{$0} <filename>"
end
