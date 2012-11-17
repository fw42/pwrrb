#!/usr/bin/env ruby
require 'logger'
require 'colorize'

if $logger == nil
	$logger = Logger.new(STDOUT)
	$logger.level = Logger::INFO

	$logger.formatter = proc do |severity, datetime, progname, msg|
		level = severity[0,1]
		if level == "I"
			level = "*".green
		elsif level == "D"
#			level = level.cyan
		elsif level == "W"
			level = level.yellow
		elsif level == "E" or level == "F"
			level = level.red
		end

		### More fixes for readlines which are longer than incoming logs
		if defined?(Pry) and Module.const_defined?("RbReadline")
			printf "\b" * RbReadline.rl_line_buffer.length
			printf " " * RbReadline.rl_line_buffer.length
		end

		puts "\r#{datetime.strftime("%H:%M:%S")} [#{level}] #{msg}"
#		puts "\r[#{level}] #{msg}"

		### Prevent async log messages from screwing up the Pry readline
		### this is getting annoying :-(
		if defined?(Pry) and Module.const_defined?("RbReadline") and !$pry_blocked
			RbReadline.rl_refresh_line(nil,nil)
		end

		""
	end
end
