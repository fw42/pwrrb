#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../pwrcall.rb'

class Stuff
	def add(a,b)
		a+b
	end

	def sleep(n)
		Pwr.sleep(n)
		return "Slept for #{n} seconds"
	end
end

Pwr.run do
	node = PwrNode.new()
	node.register(Stuff.new, "foobar")
#	node.listen_plain("0.0.0.0", 10001, ['bson', 'json']) {}
	node.listen_psk("0.0.0.0", 10001, ['bson', 'json']) {}
#	node.listen_ssl("0.0.0.0", 10001, ['bson', 'json']) {}
end
