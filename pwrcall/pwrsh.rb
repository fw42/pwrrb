#!/usr/bin/env ruby
require 'rb-readline'
require 'pry'
require 'optparse'
require File.expand_path("../pwrcall.rb", __FILE__)
require File.expand_path("../../pwrtools/nonblocking_keyboard.rb", __FILE__)

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

	opts.on('-p', '--plain', 'Connect plain (unencrypted)') do
		options[:plain] = true
	end
end
optparse.parse!

Pwr.run do
	PwrFiber.new{
		EM.open_keyboard(NonblockingKeyboard) do |kb|
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
				if options[:plain] and URI(options[:url]).port == URI::PWRCALL::DEFAULT_PORT
					$logger.warn("Sure that you use the right port?")
				end
				obj, pwr = node.open_url(options[:url], nil, !options[:plain])
			end

			Pry.prompt = [
				proc { |obj, nest_level| "pwr> " },
				proc { |obj, nest_level| "pwr> " }
			]

			### Prevent async log messages from screwing up the Pry readline
			pry_original_print = Pry.config.print
			Pry.config.print = Proc.new do |out,val|
				printf "\r"
				pry_original_print.call(out,val)
				$pry_blocked = false
			end

			Pry.config.hooks.add_hook(:after_read, :fix_line_stuff) do
				$pry_blocked = true
			end

			binding.pry({ :quiet => true })
		end
	}.resume().wait()
	Pwr.stop()
end
