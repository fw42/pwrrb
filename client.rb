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

def mysleep(n)
	f = Fiber.current
	EventMachine::Timer.new(n) do f.resume end
	Fiber.yield
end

begin
	EventMachine::run {
		Fiber.new{

#			pwr = PwrCall.connect("localhost", 10000)
			pwr = PwrCall.connect("localhost", 10001, ['bson'])
			pwr.register(Hello.new, "hellocap")

			Fiber.new{
				puts "23 + 42 = #{pwr.call("foobar", "add", 23, 42).result()}"
				puts "17 + 42 = #{pwr.call("foobar", "add", 17, 42).result()}"
			}.resume

			Fiber.new{
#				pwr.call("foobar", "callme", "hellocap", "hello_sleep")
				res = pwr.call("foobar", "add", 17, 5)
				mysleep(2)
				puts "17 + 5 = #{res.result()}"
			}.resume

			# TODO: terminate iff all results came

		}.resume
	}
rescue Interrupt
	puts "Exiting."
end
