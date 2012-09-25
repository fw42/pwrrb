#!/usr/bin/env ruby
require 'eventmachine'
require File.dirname(__FILE__) + '/../pwrtls.rb'

class EchoServer < PwrConnection
	def receive_data(data)
		puts data
	end
end

Pwr.run do
	pwr = PwrTLS::listen("localhost", 10003, EchoServer.new) {}
end
