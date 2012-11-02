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
					EM.open_keyboard(NonblockingKeyboard) do
						block.yield
					end
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

	def self.exec(cmd, timeout=nil)
		f = Fiber.current
		output = { stdout: "", stderr: "" }
		EM::SystemCommand.execute cmd do |on|
			if timeout
				timer = EM::Timer.new(timeout) do
					$logger.warn("Sending SIGTERM to #{on.pid} after #{timeout}s timeout.")
					output[:info] = [] unless output[:info]
					output[:info] << "Timeout waiting for process to exit (#{timeout}s)"
					begin
						Process.kill 'TERM', on.pid
						output[:timeout] = true
						[ :stdin, :stderr, :stdout ].each do |fd|
							on.send(fd).close_connection
						end
					rescue Errno::ESRCH => err
						$logger.warn("Failed to TERM process #{on.pid}: #{err.to_s}")
					end
				end
			end

			on.stdout.data do |data|
				output[:stdout] += data
			end

			on.stderr.data do |data|
				output[:stderr] += data
			end

			on_exit = lambda do |ps|
				timer.cancel if timer
				f.resume([ps.status.exitstatus || (128 + ps.status.termsig), output])
			end

			on.success do |ps| on_exit.call(ps) end
			on.failure do |ps|
				output[:info] = [] unless output[:info]
				output[:info] << ps.status.to_s
				on_exit.call(ps)
			end
		end
		Fiber.yield
	end

	def self.pry(local_binding, prompt="pwr> ")
		unless defined?(Pry)
			$logger.warn("Pry not available")
			return
		end

		unless defined?(RbReadline)
			$logger.warn("RbReadline not available")
			return
		end

		Pry.prompt = [
			proc { |obj, nest_level| prompt },
			proc { |obj, nest_level| prompt }
		]

		### Prevent async log messages from screwing up the Pry readline
		pry_original_print = Pry.config.print
		Pry.config.print = Proc.new do |out,val|
			printf "\r"
			pry_original_print.call(out,val)
			$pry_blocked = false
		end
		pry_original_exception_handler = Pry.config.exception_handler
		Pry.config.exception_handler = Proc.new do |out,val|
			printf "\r"
			pry_original_exception_handler.call(out,val)
			$pry_blocked = false
		end
		Pry.config.hooks.add_hook(:after_read, :fix_line_stuff) do
			$pry_blocked = true
		end

		local_binding.pry({ :quiet => true })
	end
end
