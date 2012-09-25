#!/usr/bin/env ruby
require 'eventmachine'
require File.dirname(__FILE__) + '/chat.rb'
require File.dirname(__FILE__) + '/../pwrtls.rb'

begin
	EventMachine::run {
		pwr = PwrTLS::listen("localhost", 10003, ChatExample.new) {}
	}
rescue Interrupt
	puts "Exiting."
end
