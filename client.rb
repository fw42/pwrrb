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

EventMachine::run {
	Fiber.new{

#		pwr = PwrCall.connect("137.226.161.231", 10000)
		pwr = PwrCall.connect("localhost", 10000)

		Fiber.new{
			puts "Now calling add(23,42)..."
			res = pwr.call("foobar", "add", 23, 42)
			puts "... add(23,42) returned #{res}"

			puts "Now calling add(17,42)..."
			res = pwr.call("foobar", "add", 17, 42)
			puts "... add(17,42) returned #{res}"
		}.resume

		Fiber.new{
#			pwr.register(Hello.new, "hellocap")
#			puts "Now calling callme(hello_sleep)..."
#			pwr.call("foobar", "callme", "hellocap", "hello_sleep")
#			puts "callme() called"

			puts "Now calling add(17,5)..."
			res = pwr.call("foobar", "add", 17, 5)
			puts "... add(17,5) returned #{res}"
		}.resume

	}.resume
}
