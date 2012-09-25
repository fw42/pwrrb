#!/usr/bin/env ruby
require 'logger'
require 'colorize'

if $logger == nil
	$logger = Logger.new(STDOUT)
#	$logger.level = Logger::INFO

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
#		puts "#{datetime.strftime("%H:%M:%S")} [#{level}] #{msg}"
		puts "\r[#{level}] #{msg}"
	end
end
