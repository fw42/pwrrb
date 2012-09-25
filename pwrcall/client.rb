#!/usr/bin/env ruby
require 'eventmachine'
require './pwrcall.rb'

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

			if (pwr = node.connect("localhost", 10001, ['bson'])) == nil
#			if (pwr = node.connect_pwrtls("localhost", 10005, ['bson'])) == nil
				EventMachine::stop_event_loop
			end

			# Sleep. This is "blocking".
			pwr.call("foobar", "sleep", 1).result()

			# "Thread" 1
			f1 = PwrFiber.new{
				puts "23 + 42 = #{pwr.call("foobar", "add", 23, 42).result()}"
				puts "17 + 42 = #{pwr.call("foobar", "add", 17, 42).result()}"
				res = pwr.call("foobar", "callme", "hello", "hello", "parameter eins", "parameter zwei").result()
				puts res.inspect
			}
			f1.resume

			# "Thread" 2
			f2 = PwrFiber.new{
				pwr.call("foobar", "sleep", 5).result()
				puts "17 + 5 = #{pwr.call("foobar", "add", 17, 5).result()}"
			}
			f2.resume

			# Wait for threads to finish
			f1.wait()
			f2.wait()
			EventMachine::stop_event_loop

		}.resume
	}
rescue Interrupt
	puts "Exiting."
end
