#!/usr/bin/env ruby
require 'eventmachine'
require 'base64'
require './pwrcall.rb'

class Stuff
	def add(a,b)
		a+b
	end

	def sleep(n)
		f = Fiber.current
		EventMachine::Timer.new(n) do f.resume end
		Fiber.yield
	end
end

begin
	EventMachine::run do
		Fiber.new{
			node = PwrNode.new()
			node.register(Stuff.new, "foobar")
			node.listen("0.0.0.0", 10001, ['bson']) {}
		}.resume
	end
rescue Interrupt
	puts "Exiting."
end
