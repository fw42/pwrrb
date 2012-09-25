#!/usr/bin/env ruby
require 'eventmachine'
require File.dirname(__FILE__) + '/../pwrtls.rb'

class EchoClient < PwrConnection
	def receive_data(data)
		puts data
	end
end

Pwr.run do
	pwr = PwrTLS::connect("localhost", 10003, EchoClient.new)
end
