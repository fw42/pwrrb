#!/usr/bin/env ruby
require 'eventmachine'
require File.dirname(__FILE__) + '/chat.rb'
require File.dirname(__FILE__) + '/../pwrtls.rb'

begin
	EventMachine::run {
		Fiber.new{
			pwr = PwrTLS::connect("localhost", 10003, ChatExample.new)
			puts pwr.inspect
		}.resume
	}
rescue Interrupt
	puts "Exiting."
end
