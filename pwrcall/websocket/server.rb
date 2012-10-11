#!/usr/bin/env ruby
require File.expand_path("../../../pwrcall.rb", __FILE__)
require File.expand_path("../pwrws.rb", __FILE__)

class Example
	def add(*args)
		args.inject(&:+)
	end

	def hello(*msg)
		"Hello " + msg.inspect
	end
end

$logger.level = Logger::DEBUG

thin = Rack::Handler.get('thin')
node = PwrNode.new()
reqh = WebRequestHandler.new(node)

Pwr.run do
	node.listen_plain("0.0.0.0", 10004) {}
	node.listen_pwrtls("0.0.0.0", 10005, File.expand_path("../../example_server_keypair", __FILE__)) {}
	thin.run(reqh.method(:request), :Port => 10006)

	node.register Example.new, "example"
end
