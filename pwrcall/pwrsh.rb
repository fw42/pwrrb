#!/usr/bin/env ruby
require 'optparse'
require File.expand_path("../pwrcall.rb", __FILE__)

options = {}
optparse = OptionParser.new do |opts|
	opts.on('-h', '--help', 'Display help') do
		puts opts
		exit
	end

	opts.on('-l', '--listen', 'Listen as server') do
		options[:listen] = true
	end

	opts.on('-o', '--openurl URL', 'Open a pwrcall URL') do |u|
		options[:url] = u
	end
end
optparse.parse!

Pwr.run do
	node = PwrNode.new()
	pwr = obj = nil

	if options[:listen]
		pwr = []
		node.listen_plain("0.0.0.0", 10004) { |p| pwr << p }
		node.listen_pwrtls("0.0.0.0", 10005,
			File.expand_path("../examples/example_server_keypair", __FILE__)
		) { |p| pwr << p }
	end

	if options[:url]
		obj, pwr = node.open_url(options[:url], nil)
	end

	Pwr.pry(binding)
	Pwr::stop
end
