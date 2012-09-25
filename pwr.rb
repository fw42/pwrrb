#!/usr/bin/env ruby
require 'eventmachine'
require 'fiber'
require File.dirname(__FILE__) + '/pwrtools/pwrlogger.rb'
require File.dirname(__FILE__) + '/pwrtools/pwrconnection.rb'
require File.dirname(__FILE__) + '/pwrtools/pwrunpackers.rb'

class Pwr
	def self.run(&block)
		begin
			EventMachine::run do
				Fiber.new{ block.yield }.resume
			end
		rescue Interrupt
			$logger.info("Exiting.")
		end
	end
end
