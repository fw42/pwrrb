#!/usr/bin/env ruby
require File.expand_path("../../pwrtls.rb", __FILE__)

class EchoClient < PwrConnection
	def receive_data(data)
		puts "Server sent " + data.inspect
	end
	def connection_established()
		$logger.info("Connected to Echo Server! Yeah!")
		@fiber.resume(true)
	end
end

module KeyboardHandler
	include EM::Protocols::LineText2
	def initialize(echo)
		@echo = echo
	end
	def receive_line(data)
		@echo.send(data)
	end
end

Pwr.run do
	pwr = PwrTLS::connect("localhost", 10003, EchoClient.new)
	EM.open_keyboard(KeyboardHandler, pwr)
end
