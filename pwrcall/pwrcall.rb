#!/usr/bin/env ruby
require File.expand_path("../../pwr.rb", __FILE__)
require File.expand_path("../../pwrtls/pwrtls.rb", __FILE__)

require 'uri'
module URI
	class PWRCALL < Generic
		DEFAULT_PORT = 10000
		COMPONENT = [ :scheme, :userinfo, :host, :port, :path ]
		@@schemes['PWRCALL'] = PWRCALL

		def capability()
			return self.path.gsub(/^\//, "").gsub(/\/$/, "")
		end

		def fingerprint()
			return self.userinfo
		end
	end
end

class PwrObj
	def initialize(pwrcon, capability)
		@pwrcon = pwrcon
		@capability = capability
	end

	def method_missing(m, *args)
		@pwrcon.call(@capability, m, *args).result()
	end  
end

class PwrNode
	def initialize()
		@exports = {}
		@extern = {}
		@conns = {}
	end

	def register(obj, ref)
		@exports[ref] = obj
	end

	def obj(ref)
		@exports[ref]
	end

	def connect(server, port, handler, packers=nil, *args)
		pwrconn = PwrCallConnection.new(self, packers)
		EventMachine::connect(server, port, handler, pwrconn, *args)
		if Fiber.yield
			return @conns[[server,port]] = pwrconn
		else
			return nil
		end
	end

	def connect_plain(server, port, packers=nil)
		connect(server, port, PwrConnectionHandlerPlain, packers)
	end

	def connect_pwrtls(server, port, packers=nil, keypair=nil, fingerprint=nil)
		connect(server, port, PwrConnectionHandlerPwrTLS, packers, keypair, fingerprint)
	end

	def open_url(url, packers=nil)
		url = URI(url) if url.class == String

		### Do we already know this capability?
		if @extern[url.capability] and @conns[[url.host, url.port]]
			return @extern[url.capability], @conns[[url.host, url.port]]
		end

		### Do we already know this connection (possibly in combination with another capability)?
		if @conns[[url.host, url.port]] == nil
			@conns[[url.host, url.port]] = connect_pwrtls(url.host, url.port, packers, nil, url.fingerprint)
		end

		@extern[url.capability] = PwrObj.new(@conns[[url.host, url.port]], url.capability)
		return @extern[url.capability], @conns[[url.host, url.port]]
	end

	def open_cap(cap, con)
		@extern[cap] = @extern[cap] || PwrObj.new(con, cap)
	end

	def listen(server, port, handler, packers=nil, keypair=nil, &block)
		EventMachine::start_server(server, port, handler, nil, keypair) do |c|
			pwrconn = PwrCallConnection.new(self, packers, true)
			c.set_connection(pwrconn)
			c.server_accepted()
			block.yield(pwrconn)
		end
		$logger.info("Listening on #{server}:#{port}")
	end

	def listen_plain(server, port, packers=nil, &block)
		listen(server, port, PwrConnectionHandlerPlain, packers, &block)
	end

	def listen_pwrtls(server, port, keypairfile=nil, packers=nil, &block)
		keypair = PwrTLS.keypair_load(keypairfile)
		listen(server, port, PwrConnectionHandlerPwrTLS, packers, keypair, &block)
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

class PwrCallConnection < PwrConnection
	OP = { request: 0, response: 1, notify: 2 }
	VERSION = "pwrcallrb_v0.1"

	attr_reader :server, :peer

	public

	def initialize(node, packers=nil, server=false)
		@node = node
		@packers = packers || PwrUnpacker.unpackers.keys
		@ready = false
		@msgid = 0
		@buf = ""
		@server = server
		@pending = {}
		super()
	end

	######

	public

	def call(ref, fn, *params)
		throw :connection_not_ready unless @ready
		@pending[@msgid] = PwrResult.new()
		send_request(@msgid, ref, fn, *params)
		@msgid += 1
		return @pending[@msgid-1]
	end

	def open_cap(cap)
		@node.open_cap(cap, self)
	end

	######

	public

	def connection_established()
		@peer = Socket.unpack_sockaddr_in(@connection_handler.get_peername)
		send_hello()
	end

	###### Callbacks

	public

	def receive_data(data)
		$logger.debug("PwrCall<< " + data.inspect)

		if !@ready
			@buf << data
			return unless @buf.index("\n")
			line, @buf = @buf.split("\n", 2)

			if hello = /^pwrcall ([^\s]*) - caps: (.*)$/.match(line)
				hello[2].split(",").map{ |cap| cap.strip }.each do |cap|
					next unless @packers.include?(cap) and PwrUnpacker.unpackers[cap]
					$logger.debug("Handshake with #{@peer[1]}:#{@peer[0]} completed. Using #{cap} packer.")
					$logger.info("PwrCall connection with #{@peer[1]}:#{@peer[0]} established")
					@ready = true
					@packer = PwrUnpacker.unpackers[cap].new()
					@fiber.resume(true) unless @server
					break
				end
				if !@ready
					$logger.error("No supported packers in common :-(")
					@fiber.resume(false) unless @server
					return
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

	def unbind()
		### PwrCall connetion was okay before, now closing
		if @peer and @ready
			$logger.info("PwrCall connection with #{@peer[1]}:#{@peer[0]} closed")
		end

		### Client is not able to open TCP connection
		if !@server and !@peer and @fiber.alive?
			$logger.error("Connection failed")
			@fiber.resume(false)
		### Client is connected via TCP, but PwrCall fails (no packers in common, ...)
		elsif @peer and !@ready
			$logger.error("Could not establish PwrCall connection with #{@peer[1]}:#{@peer[0]}")
		end

		@ready = false
		@pending.keys.each do |k|
			@pending[k].set_error("Connection lost")
		end
	end

	######

	private

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
					### Monkey patching magic, add instance variable to object at runtime :-)
					class << obj
						attr_accessor :pwrcall_current_connection
					end
					obj.pwrcall_current_connection = self
					send_response(msgid, obj.send(fn, *params))
				}.resume
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

	def send_hello()
		send("pwrcall %s - caps: %s\n" % [ VERSION, @packers.join(",") ])
	end
end

module PwrConnectionHandlerPlain
	def initialize(conn=nil)
		set_connection(conn)
	end

	###### Interface to PwrConnection

	public

	def set_connection(conn)
		@conn = conn
		@conn.set_connection_handler(self) if conn
	end

	def send(data)
		send_data(data)
	end

	######

	private

	def print_connected_msg()
		@peer = Socket.unpack_sockaddr_in(get_peername)
		$logger.info("Plain connection with #{@peer[1]}:#{@peer[0]} established") if @peer
	end

	###### Callbacks

	public

	def receive_data(data)
		@conn.receive_data(data)
	end

	def connection_completed()
		print_connected_msg()
		@conn.connection_established()
	end

	def server_accepted()
		print_connected_msg()
		@conn.connection_established()
	end

	def unbind()
		@conn.unbind() if @conn
		$logger.info("Plain connection with #{@peer[1]}:#{@peer[0]} closed") if @peer
	end
end
