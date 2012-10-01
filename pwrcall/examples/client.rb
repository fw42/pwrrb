#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../pwrcall.rb'

class Example
	def hello(*args)
		peer = "%s:%s" % @pwrcall_current_connection.peer.reverse
		puts "#{peer} called hello() on me with parameters: #{args.inspect}"
		return "Hello, parameters were: #{args.inspect}"
	end
end

Pwr.run do

	node = PwrNode.new()
	node.register(Example.new, "example")
	obj, pwr = node.open_url("pwrcall://localhost:10001/foobar")

	# Check if connection failed
	exit unless pwr

	# Sleep call. This is "blocking".
	pwr.call("sleep", 1).result()

	# ... which is equivalent to:
	obj.sleep(1)

	# "Thread" 1
	f1 = PwrFiber.new{
		puts "23 + 42 = %d" % obj.add(23, 42)
		puts "17 + 42 = %d" % obj.add(17, 42)
		puts obj.callme("example", "hello", "one", [ "two" ], { three: true })
	}.resume()

	# "Thread" 2
	f2 = PwrFiber.new{
		puts pwr.call("foobar", "sleep", 2).result()
		puts "17 + 5 = #{pwr.call("foobar", "add", 17, 5).result()}"
		puts "string concat = #{pwr.call("foobar", "add", "string", "concat").result()}"
	}.resume()

	# Wait for Fibers to finish
	f1.wait()
	f2.wait()
	Pwr.stop

end
