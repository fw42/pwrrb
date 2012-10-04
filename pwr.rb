#!/usr/bin/env ruby
require 'eventmachine'
require 'forwardable'
require 'em-systemcommand'
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

	def self.stop
		EventMachine::stop_event_loop
	end

	def self.sleep(n)
		f = Fiber.current
		EventMachine::Timer.new(n) do f.resume end
		Fiber.yield
	end

	def self.exec(cmd)
		f = Fiber.current
		output = ""
		EM::SystemCommand.execute cmd do |on|
			on.stdout.data do |data|
				output += data
			end
			on.success do
				f.resume(output)
			end
		end
		Fiber.yield
	end
end
