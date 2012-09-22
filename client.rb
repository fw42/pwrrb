#!/usr/bin/ruby1.9.1
require 'eventmachine'
require 'base64'
require './pwrcall.rb'

class Hello
	def hello(*p)
		puts "Someone called hello() on me!"
		"Hello, parameters were: #{p.inspect}"
	end

	def hello_sleep(p)
		f = Fiber.current
		EventMachine::Timer.new(5) do
			f.resume(hello(p))
		end
		Fiber.yield
	end
end

begin
	EventMachine::run {
		Fiber.new{

#			pwr = PwrCall.connect("137.226.161.231", 10000)
			pwr = PwrCall.connect("localhost", 10001)
			pwr.register(Hello.new, "hellocap")

			Fiber.new{
				res = pwr.call("foobar", "add", 23, 42)
				res = pwr.call("foobar", "add", 17, 42)
			}.resume

			Fiber.new{
#				pwr.call("foobar", "callme", "hellocap", "hello_sleep")
				res = pwr.call("foobar", "add", 17, 5)
			}.resume

		}.resume
	}
rescue Interrupt
	puts "Exiting."
end
