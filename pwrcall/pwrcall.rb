#!/usr/bin/env ruby
require 'eventmachine'
require 'fiber'
require File.dirname(__FILE__) + '/pwrunpackers.rb'
require File.dirname(__FILE__) + '/pwrlogger.rb'
require File.dirname(__FILE__) + '/pwrtls.rb'

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
		pwrconn = PwrConnection.new(self, packers)
		EventMachine::connect(server, port, PwrConnectionHandlerPlain, pwrconn)
		return Fiber.yield ? pwrconn : nil
	end

	def connect_pwrtls(server, port, packers=nil)
		pwrconn = PwrConnection.new(self, packers)
		EventMachine::connect(server, port, PwrConnectionHandlerPwrTLS, pwrconn)
		return Fiber.yield ? pwrconn : nil
	end

	def listen(server, port, packers=nil, &block)
		EventMachine::start_server(server, port, PwrConnectionHandlerPlain) do |c|
			pwrconn = PwrConnection.new(self, packers, true)
			c.set_connection(pwrconn)
			pwrconn.connection_completed
			block.yield(pwrconn)
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

	def error()
		return @error
	end

	def set_error(error=nil)
		@error = true
		resume(error)
	end

	def set(result=nil)
		resume(result)
	end

	private
	def resume(r)
		@fiber.resume(r) if @fiber.alive?
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

	def resume(*args)
		super(*args)
		return self
	end

	def wait()
		@r.result()
	end
end

class PwrConnection
	OP = { request: 0, response: 1, notify: 2 }
	VERSION = "pwrcallrb_v0.1"

	public

	def initialize(node, packers=nil, server=false)
		@node = node
		@fiber = Fiber.current
		@packers = packers || PwrUnpacker.unpackers.keys
		@ready = false
		@msgid = 0
		@buf = ""
		@server = server
		@pending = {}
	end

	def call(ref, fn, *params)
		@pending[@msgid] = PwrResult.new()
		send_request(@msgid, ref, fn, *params)
		@msgid += 1
		return @pending[@msgid-1]
	end

	def set_connection_handler(handler)
		@connection_handler = handler
	end

	######

	public

	def connection_completed
		connection_established
	end

	def receive_data(data)
		$logger.debug("PwrCall<< " + data.inspect)

		if !@ready
			@buf << data
			return unless @buf.index("\n")
			line, @buf = @buf.split("\n", 2)

			if hello = /^pwrcall ([^\s]*) - caps: (.*)$/.match(line)
				hello[2].split(",").map{ |cap| cap.strip }.each do |cap|
					next unless @packers.include?(cap) and PwrUnpacker.unpackers[cap]
					$logger.debug("Handshake with #{@ip}:#{@port} completed. Using #{cap} packer.")
					$logger.info("PwrCall connection with #{@ip}:#{@port} established")
					@ready = true
					@packer = PwrUnpacker.unpackers[cap].new()
					@fiber.resume(true) unless @server
					break
				end
				if !@ready
					$logger.error("No supported packers in common :-(")
					unbind()
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

	def unbind
		if @ip and @ready
			$logger.info("PwrCall connection with #{@ip}:#{@port} closed")
		elsif !@server and @fiber.alive?
			$logger.error("Connection failed")
			@fiber.resume(false)
		end
	end

	######

	private

	def connection_established()
		@port, @ip = Socket.unpack_sockaddr_in(@connection_handler.get_peername)
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
		if error
			@pending[msgid].set_error(error)
		else
			@pending[msgid].set(result)
		end
	end

	def handle_unknown(opcode, msgid)
		$logger.debug("Error: <#{msgid}> Received unknown opcode #{opcode}")
		send_error(msgid, "unknown opcode #{opcode}")
	end

	######

	private

	def send(data)
		$logger.debug("PwrCall>> " + data.inspect)
		@connection_handler.send(data)
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

module PwrConnectionHandlerPlain
	def initialize(conn=nil)
		set_connection(conn)
	end

	def set_connection(conn)
		@conn = conn
		@conn.set_connection_handler(self) if conn
	end

	def unbind()
		@conn.unbind() if @conn
		$logger.info("Plain connection with #{@ip}:#{@port} closed") if @ip
	end

	def receive_data(data)
		@conn.receive_data(data)
	end

	def connection_completed(*args)
		@port, @ip = Socket.unpack_sockaddr_in(get_peername)
		$logger.info("Plain connection with #{@ip}:#{@port} established") if @ip
		@conn.connection_completed(*args)
	end

	def send(data)
		send_data(data)
	end
end
