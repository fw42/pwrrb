#!/usr/bin/env ruby
require File.expand_path("../../pwrtls.rb", __FILE__)

class EchoServer < PwrConnection
	def connection_established()
		send("Welcome to the PwrTLS example EchoServer!")
		puts "Someone connected to our EchoServer!"
	end
	def receive_data(data)
		puts "Echo " + data.inspect
		send(data)
	end
end

Pwr.run do
	pwr = PwrTLS::listen("localhost", 10003, EchoServer) {}
end
