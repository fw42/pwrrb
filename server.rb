#!/usr/bin/ruby1.9.1
require 'eventmachine'
require 'base64'
require './pwrcall.rb'

class Mathe
	def add(a,b)
		a+b
	end
end

EventMachine::run {
	Fiber.new{
		PwrCall.listen("0.0.0.0", 10000) do |pwr|
			pwr.register(Mathe.new, "foobar")
		end
	}.resume
}
