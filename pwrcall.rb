#!/usr/bin/env ruby
require 'eventmachine'
require 'fiber'
require './pwrunpackers.rb'
require 'logger'

$logger = Logger.new(STDOUT)
#$logger.level = Logger::INFO

$logger.formatter = proc do |severity, datetime, progname, msg|
	puts "[#{datetime.strftime("%H:%M:%S")}] #{severity[0,1]}: #{msg}"
end

class PwrNode
	def initialize()
		@exports = {}
	end

	def register(obj, ref)
		@exports[ref] = obj
	end

	def obj(ref)
		@exports[ref]
	end

	def connect(server, port, packers=nil)
		pwr = EventMachine::connect(server, port, PwrConnection, self, packers)
		Fiber.yield
		return pwr
	end

	def listen(server, port, packers=nil, &block)
		EventMachine::start_server(server, port, PwrConnection, self, packers, true) do |c|
			c.connection_established
			block.yield(c)
		end
	end
end

class PwrResult
	def initialize()
		@fiber = Fiber.current
	end

	def result()
		Fiber.yield
	end

	def set(result=nil)
		@fiber.resume(result) if @fiber.alive?
	end
end

class PwrFiber < Fiber
	def initialize(&block)
		@r = PwrResult.new()
		super do
			block.yield
			@r.set()
		end
	end

	def wait()
		@r.result()
	end
end

module PwrConnection
	OP = { request: 0, response: 1, notify: 2 }
	VERSION = "pwrcallrb_v0.1"

	def initialize(node, packers=nil, server=false)
		@node = node
		@ready = false
		@msgid = 0
		@fiber = Fiber.current
		@packers = packers || PwrUnpacker.unpackers.keys
		@buf = ""
		@server = server
		@pending = {}
	end

	def unbind
		$logger.info("Connection with #{@ip}:#{@port} closed") if @ip
		@fiber.resume if !@server and @fiber.alive?
	end

	def connection_completed
		connection_established
	end

	def receive_data(data)
		$logger.debug("<< " + data.inspect)

		if !@ready
			@buf << data
			return unless @buf.index("\n")
			line, @buf = @buf.split("\n", 2)

			if hello = /^pwrcall ([^\s]*) - caps: (.*)$/.match(line)
				hello[2].split(",").map{ |cap| cap.strip }.each do |cap|
					next unless @packers.include?(cap) and PwrUnpacker.unpackers[cap]
					$logger.debug("Handshake with #{@ip}:#{@port} completed. Using #{cap} packer.")
					@ready = true
					@packer = PwrUnpacker.unpackers[cap].new()
					@fiber.resume unless @server
					break
				end
				if !@ready
					$logger.fatal("No supported packers in common :-(")
				end
				data = @buf
			end
		end

		if @ready
			@packer.feed(data)
			while unpacked = @packer.next
				handle_packet(unpacked)
			end
			return
		end
	end

	######

	def call(ref, fn, *params)
		@pending[@msgid] = PwrResult.new()
		send_request(@msgid, ref, fn, *params)
		@msgid += 1
		return @pending[@msgid-1]
	end

	######

	def connection_established
		@port, @ip = Socket.unpack_sockaddr_in(get_peername)
		$logger.info("Connection with #{@ip}:#{@port} established")
		send_hello()
	end

	def handle_packet(packet)
		opcode, msgid = packet[0..1]
		if opcode == OP[:request] then
			handle_request(msgid, packet[2], packet[3], packet[4])
		elsif opcode == OP[:response] then
			handle_response(msgid, packet[2], packet[3])
		elsif opcode == OP[:notify] then
			$logger.warn("Notify received. Not implemented yet! :-(")
		else
			handle_unknown(opcode, msgid)
		end
	end

	def handle_request(msgid, ref, fn, params)
		$logger.info("Incoming req.: <#{msgid}> #{ref}.#{fn}(#{params.inspect[1..-2]})")
		if obj = @node.obj(ref)
			if obj.respond_to?(fn)
				Fiber.new{ 
				send_response(msgid, obj.send(fn, *params)) }.resume
			else
				send_error(msgid, "#{ref} has no method #{fn}")
			end
		else
			send_error(msgid, "#{ref} does not exist")
		end
	end

	def handle_response(msgid, error, result)
		$logger.info("Incoming res.: <#{msgid}> #{[error, result].inspect}")
		@pending[msgid].set(error ? error : result)
	end

	def handle_unknown(opcode, msgid)
		$logger.debug("Error: <#{msgid}> Received unknown opcode #{opcode}")
		send_error(msgid, "unknown opcode #{opcode}")
	end

	######

	def send(data)
		$logger.debug(">> " + data.inspect)
		send_data(data)
	end

	def send_error(msgid, error)
		send(@packer.pack([ OP[:response], msgid, error, nil ]))
	end

	def send_request(msgid, ref, fn, *params)
		$logger.info("Outgoing req.: <#{msgid}> #{ref}.#{fn}(#{params.inspect[1..-2]})")
		send(@packer.pack([ OP[:request], msgid, ref, fn, params ]))
	end

	def send_response(msgid, result)
		$logger.info("Outgoing res.: <#{msgid}> #{result.inspect}")
		send(@packer.pack([ OP[:response], msgid, nil, result ]))
	end

	def send_hello
		send("pwrcall %s - caps: %s\n" % [ VERSION, @packers.join(",") ])
	end
end
