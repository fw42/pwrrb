#!/usr/bin/env ruby
require 'eventmachine'
require './pwrtls.rb'

begin
	EventMachine::run {
		pwr = EventMachine::connect("localhost", 10003, PwrTLS)
	}
rescue Interrupt
	puts "Exiting."
end
