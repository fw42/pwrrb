#!/usr/bin/env ruby
require 'eventmachine'
require '../pwrcall.rb'

class Hello
	def hello(*p)
		puts "Someone called hello() on me with parameters: #{p.inspect}"
		return "Hello, parameters were: #{p.inspect}"
	end
end

begin
	EventMachine::run {
		Fiber.new{

			node = PwrNode.new()
			node.register(Hello.new, "hello")

			pwr = node.connect("localhost", 10001, ['bson'])
#			pwr = node.connect_pwrtls("localhost", 10005, ['bson'])

			# Check if connection failed
			exit unless pwr

			# Sleep. This is "blocking".
			pwr.call("foobar", "sleep", 2).result()

			# "Thread" 1
			f1 = PwrFiber.new{
				puts "23 + 42 = #{pwr.call("foobar", "add", 23, 42).result()}"
				puts "17 + 42 = #{pwr.call("foobar", "add", 17, 42).result()}"
				res = pwr.call("foobar", "callme", "hello", "hello", "parameter eins", "parameter zwei").result()
				puts res.inspect
			}.resume()

			# "Thread" 2
			f2 = PwrFiber.new{
				pwr.call("foobar", "sleep", 5).result()
				puts "17 + 5 = #{pwr.call("foobar", "add", 17, 5).result()}"
			}.resume()

			# Wait for Fibers to finish
			f1.wait()
			f2.wait()
			EventMachine::stop_event_loop

		}.resume
	}
rescue Interrupt
	puts "Exiting."
end
