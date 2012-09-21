#!/usr/bin/ruby1.9.1
require 'eventmachine'
require 'fiber'
require './pwrunpackers.rb'

class PwrCall
	def initialize(pwr)
		@pwr = pwr
	end

	def self.connect(server, port, packers=nil)
		pwr = EventMachine::connect(server, port, PwrCallConnection, packers)
		Fiber.yield
		PwrCall.new(pwr)
	end

	def self.listen(server, port, packers=nil, &block)
		EventMachine::start_server(server, port, PwrCallConnection, packers, true) do |srv|
			block.yield(srv)
		end
	end

	def method_missing(m, *args, &block)
		@pwr.method(m).call(*args)
	end  
end

module PwrCallConnection

	VERSION = "PWR_Ruby_1.9.3.1.3_itsec_cloud_git_42"
	OP = { request: 0, response: 1, notify: 2 }

	######

	def initialize(packers=nil, server=false)
		@ready = false
		@msgid = 0
		@pending = {}
		@exports = {}
		@fiber = Fiber.current
		@packers = packers || PwrUnpacker.unpackers.keys
		@buf = ""
		@server = server
	end

	def post_init
		send_hello()
	end

	def receive_data(data)
		puts "<< #{data.inspect}"

		if !@ready
			@buf << data
			return unless @buf.index("\n")
			line, @buf = @buf.split("\n", 2)

			if hello = /^pwrcall ([^\s]*) - caps: (.*)$/.match(line)
				hello[2].split(",").map{ |cap| cap.strip }.each do |cap|
					next unless @packers.include?(cap) and PwrUnpacker.unpackers[cap]
					@ready = true
					@packer = PwrUnpacker.unpackers[cap].new()
					@fiber.resume unless @server
				end
				if !@ready
					STDERR.puts "No supported packers in common :-("
					return
				end
				data = @buf
			end
		end

		if @ready
			@packer.feed(data)
			if unpacked = @packer.next
				handle_packet(unpacked)
			end
			return
		end
	end

	######

	def call(ref, fn, *params)
		@pending[@msgid] = Fiber.current
		send_request(@msgid, ref, fn, *params)
		@msgid += 1
		Fiber.yield
	end

	def register(obj, ref)
		@exports[ref] = obj
	end

	######

	def handle_packet(packet)
		opcode, msgid = packet[0..1]

		if opcode == OP[:request] then
			handle_request(msgid, packet[2], packet[3], packet[4])
		elsif opcode == OP[:response] then
			handle_error(msgid, packet[2], packet[3])
		elsif opcode == OP[:notify] then
			# TODO
		else
			handle_unknown(opcode, msgid)
		end
	end

	def handle_request(msgid, ref, fn, params)
		puts "New request: #{fn}(#{params.inspect})"
		if obj = @exports[ref]
			if obj.respond_to?(fn)
				Fiber.new{ send_result(msgid, obj.send(fn, *params)) }.resume
			else
				send_error(msgid, "#{ref} has no method #{fn}")
			end
		else
			send_error(msgid, "#{ref} does not exist")
		end
	end

	def handle_error(msgid, error, result)
		@pending[msgid].resume(error ? error : result)
	end

	def handle_unknown(opcode, msgid)
		send_error(msgid, "unknown opcode #{opcode}")
	end

	######

	def send(data)
		puts ">> #{data.inspect}"
		send_data(data)
	end

	def send_error(msgid, error)
		send(@packer.pack([ OP[:response], msgid, error, nil ]))
	end

	def send_request(msgid, ref, fn, *params)
		send(@packer.pack([ OP[:request], msgid, ref, fn, params ]))
	end

	def send_result(msgid, result)
		send(@packer.pack([ OP[:response], msgid, nil, result ]))
	end

	def send_hello
		send("pwrcall %s - caps: %s\n" % [ VERSION, @packers.join(",") ])
	end
end
