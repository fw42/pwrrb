#!/usr/bin/env ruby
require File.expand_path("../../pwrcall.rb", __FILE__)
require File.expand_path("../pwrws.rb", __FILE__)

class Example
	include PwrClassPublic

	def add(*args)
		args.inject(&:+)
	end

	def hello
		"Hello World!"
	end

	def callme(ref, fn, *args)
		@pwrcall_current_connection.call(ref, fn, *args).result()
	end

	def sleep(n)
		Pwr.sleep(n)
	end

	def sleep_callme(*args)
		sleep(2)
		callme(*args)
	end
end

thin = Rack::Handler.get('thin')
node = PwrNode.new()
reqh = WebRequestHandler.new(node)
PwrCallProxy.new(node, "proxy")

node.register Example.new, "example"

Pwr.run do
	node.listen_plain("0.0.0.0", 10004) {}
	node.listen_pwrtls("0.0.0.0", 10005, File.expand_path("../../examples/example_server_keypair", __FILE__)) {}
	thin.run(reqh.method(:request), :Port => 10006)
	Pwr.pry(binding)
end
