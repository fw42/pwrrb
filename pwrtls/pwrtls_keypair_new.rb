#!/usr/bin/env ruby
require File.expand_path("../pwrtls.rb", __FILE__)

if ARGV.length == 1
	PwrTLS.keypair_init(ARGV[0])
else
	puts "Usage: #{$0} <filename>"
end
