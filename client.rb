#!/usr/bin/env ruby
require 'eventmachine'
require 'base64'
require './pwrcall.rb'

class Hello
	def hello(*p)
		puts "Someone called hello() on me!"
		"Hello, parameters were: #{p.inspect}"
	end

	def hello_sleep(p)
		mysleep(5)
		hello()
	end

	def mysleep(n)
		f = Fiber.current
		EventMachine::Timer.new(n) do f.resume end
		Fiber.yield
	end
end

begin
	EventMachine::run {
		Fiber.new{

			node = PwrNode.new()
			node.register(Hello.new, "hellocap")

#			pwr = node.connect("localhost", 10000)
			pwr = node.connect("localhost", 10001, ['bson'])

			f1 = PwrFiber.new{
				puts "23 + 42 = #{pwr.call("foobar", "add", 23, 42).result()}"
				puts "17 + 42 = #{pwr.call("foobar", "add", 17, 42).result()}"
			}

			f2 = PwrFiber.new{
				pwr.call("foobar", "sleep", 3).result()
				puts "17 + 5 = #{pwr.call("foobar", "add", 17, 5).result()}"
			}

			f1.resume
			f2.resume

			f1.wait()
			f2.wait()
			EventMachine::stop_event_loop

		}.resume
	}
rescue Interrupt
	puts "Exiting."
end
