#!/usr/bin/env ruby
require 'eventmachine'
require 'forwardable'
require 'em-systemcommand'
require 'fiber'
require File.expand_path("../pwrtools/pwrlogger.rb", __FILE__)
require File.expand_path("../pwrtools/pwrconnection.rb", __FILE__)
require File.expand_path("../pwrtools/pwrunpackers.rb", __FILE__)
require File.expand_path("../pwrtools/nonblocking_keyboard.rb", __FILE__)

begin
	require 'rb-readline'
	require 'pry'
rescue LoadError
end

class Pwr
	def self.run(&block)
		begin
			EventMachine::run do
				Fiber.new{
					PwrFiber.new{
						EM.open_keyboard(NonblockingKeyboard) do
							block.yield
						end
					}.resume().wait()
					Pwr.stop
				}.resume()
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

			on_exit = lambda do |ps|
				output = output.split("\n") if output
				f.resume([ps.status.exitstatus, output])
			end

			on.success do |ps| on_exit.call(ps) end
			on.failure do |ps| on_exit.call(ps) end
		end
		Fiber.yield
	end

	def self.pry(local_binding)
		unless defined?(Pry) and defined?(RbReadline)
			$logger.warn("Pry not available")
			return
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

		local_binding.pry({ :quiet => true })
	end
end
