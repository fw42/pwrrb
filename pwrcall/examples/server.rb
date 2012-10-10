#!/usr/bin/env ruby
require File.expand_path("../../pwrcall.rb", __FILE__)

class Stuff
	def add(*args)
		args.inject(&:+)
	end

	def sleep(n)
		Pwr.sleep(n)
		return "Slept for #{n} seconds"
	end

	def callme(cap, *args)
		@pwrcall_current_connection.call(cap, *args).result()
	end

	def exec(cmd)
		Pwr.exec(cmd)
	end
end

Pwr.run do
	node = PwrNode.new()
	node.register(Stuff.new, "foobar")

	node.listen_plain("0.0.0.0", 10004) {}
	node.listen_pwrtls("0.0.0.0", 10005, File.expand_path("../example_server_keypair", __FILE__)) {}
end
