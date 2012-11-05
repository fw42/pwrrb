#!/usr/bin/env ruby
require File.expand_path("../../pwrcall.rb", __FILE__)

class Example
	_pwr_expose :hello

	def hello(*args)
		peer = "%s:%s" % @pwrcall_current_connection.peer.reverse
		puts "#{peer} called hello() on me with parameters: #{args.inspect}"
		return "Hello, parameters were: #{args.inspect}"
	end
end

Pwr.run do
	node = PwrNode.new()
	node.register(Example.new, "example")
	obj, pwr = node.open_url("pwrcall://21bc7f3c3956e5aa04a6dc33fea9d2b913b4157c@localhost:10005/Zm9vYmFy")

	# Check if connection failed
	exit unless pwr

	# Sleep call. This is "blocking".
	pwr.call("foobar", "sleep", 1).result()

	# ... which is equivalent to:
	obj.sleep(1)

	# "Thread" 1
	f1 = PwrFiber.new{
		# Execute some remote command and get the output
		puts "Localtime on server: " + obj.exec("sleep 1; date")[1]["stdout"].join

		puts "23 + 42 = %d" % obj.add(23, 42)
		puts "17 + 42 = %d" % obj.add(17, 42)
		puts obj.callme("example", "hello", "one", [ "two" ], { three: true })
	}

	# "Thread" 2
	f2 = PwrFiber.new{
		puts "17 + 5 = #{pwr.call("foobar", "add", 17, 5).result()}"
		puts "string concat = #{pwr.call("foobar", "add", "string", "concat").result()}"
	}

	# Start fibers
	f1.resume()
	f2.resume()

	# Wait for Fibers to finish
	f1.wait()
	f2.wait()
	Pwr.stop
end
