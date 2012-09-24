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

def mysleep(n)
	f = Fiber.current
	EventMachine::Timer.new(n) do f.resume end
	Fiber.yield
end

begin
	EventMachine::run do
		Fiber.new{
			PwrCall.listen("0.0.0.0", 10001) do |pwr|
				pwr.register(Mathe.new, "foobar")
			end
		}.resume
	end
rescue Interrupt
	puts "Exiting."
end
