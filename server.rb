#!/usr/bin/ruby1.9.1
require 'eventmachine'
require 'base64'
require './pwrcall.rb'

class Mathe
	def add(a,b)
		a+b
	end

	# TODO: fixme
	def sleepadd(a,b)
		mysleep(1)
		a+b
	end
end

class Callme
	def callme()
		
	end
end

def mysleep(n)
	f = Fiber.current
	EventMachine::Timer.new(n) do f.resume end
	Fiber.yield
end

begin
	EventMachine::run do
		Fiber.new{
			node = PwrNode.new()
			node.register(Mathe.new, "foobar")
			node.listen("0.0.0.0", 10001) {}
		}.resume
	end
rescue Interrupt
	puts "Exiting."
end
