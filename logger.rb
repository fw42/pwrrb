#!/usr/bin/env ruby
require 'logger'

$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO

$logger.formatter = proc do |severity, datetime, progname, msg|
	puts "[#{datetime.strftime("%H:%M:%S")}] #{severity[0,1]}: #{msg}"
end
