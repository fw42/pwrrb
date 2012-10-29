#!/usr/bin/env ruby
require File.expand_path("../../pwr.rb", __FILE__)
require File.expand_path("../../pwrtls/pwrtls.rb", __FILE__)

require 'base64'
require 'uri'
module URI
	class PWRCALL < Generic
		DEFAULT_PORT = 10005
		COMPONENT = [ :scheme, :userinfo, :host, :port, :path ]
		@@schemes['PWRCALL'] = PWRCALL

		def ref()
			ref = self.path.gsub(/^\//, "").gsub(/\/$/, "")
			ref = Base64.decode64(ref)
			ref == "" ? nil : ref
		end

		def fingerprint()
			return self.userinfo
		end
	end
end

class Module
	def _pwr_expose(*new)
		list = []
		if class_variable_defined?(:@@_pwr_exposed) then
			list = class_variable_get(:@@_pwr_exposed)
		end
		class_variable_set :@@_pwr_exposed, list.concat(new.map(&:to_s)).uniq

		unless self.methods.include?(:_pwr_exposed)
			define_method :_pwr_exposed do
				self.class.class_variable_get :@@_pwr_exposed
			end
		end
	end
end

class PwrCallProxy
	_pwr_expose :register

	def initialize(node, proxy_ref)
		@node = node
#		@proxy_ref = proxy_ref
		@node.register(self, proxy_ref)
	end

	def register(obj_ref, conn=@pwrcall_current_connection)
		@node.register(PwrObj.new(conn, obj_ref), obj_ref)
		return true
	end
end

class PwrObj
	attr_reader :ref, :con

	def initialize(con, ref)
		@con = con
		@ref = ref
	end

	def method_missing(m, *args)
		@con.call(@ref, m, *args).result()
	end  
end

class PwrNode
	attr_reader :conns

	def add_conn(key,conn)
		@conns[key] = conn
	end

	def del_conn(conn)
		@conns.delete_if{ |k,v| v == conn }
	end

	def initialize()
		@exports = {}
		@extern = {}
		@conns = {}
	end

	def register(obj, ref)
		$logger.info("Registered new ref \"#{Base64.encode64(ref).chomp}\" (class #{obj.class})")
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
		pwrtls = (url.fingerprint != "plain")

		### Do we already know this ref?
		if url.ref and @extern[url.ref] and @conns[[url.host, url.port]]
			return @extern[url.ref], @conns[[url.host, url.port]]
		end

		### Do we already know this connection (possibly in combination with another ref)?
		if @conns[[url.host, url.port]] == nil
			if pwrtls
				@conns[[url.host, url.port]] = connect_pwrtls(url.host, url.port, packers, nil, url.fingerprint)
			else
				@conns[[url.host, url.port]] = connect_plain(url.host, url.port, packers)
			end
		end

		if url.ref
			@extern[url.ref] = PwrObj.new(@conns[[url.host, url.port]], url.ref)
			return @extern[url.ref], @conns[[url.host, url.port]]
		else
			return nil, @conns[[url.host, url.port]]
		end
	end

	def open_ref(ref, con)
		@extern[ref] = @extern[ref] || PwrObj.new(con, ref)
	end

	def listen(server, port, handler, packers=nil, keypair=nil, &block)
		EventMachine::start_server(server, port, handler, nil, keypair) do |c|
			pwrconn = PwrCallConnection.new(self, packers, true)
			c.set_connection(pwrconn)
			c.server_accepted()
			@conns[c.get_peer] = pwrconn
			block.yield(pwrconn) if block
		end
		$logger.info("Listening on #{server}:#{port} (#{handler.to_s.gsub(/^PwrConnectionHandler/, "")})")
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
	def initialize(cache=true)
		@cache = cache
		@fiber = Fiber.current
	end

	def result()
		if @cached
			return @cached
		else
			@yield = true
			Fiber.yield
		end
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
		if @yield or !@cache
			@fiber.resume(r) if @fiber.alive?
		else
			@cached = r
		end
		return r
	end
end

class PwrFiber < Fiber
	def initialize(&block)
		@r = PwrResult.new(false)
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

	def open_ref(ref)
		@node.open_ref(ref, self)
	end

	######

	public

	def connection_established()
		@peer = @connection_handler.get_peer()
		send_hello()
	end

	###### Callback handlers

	public

	def on_ready(&block)
		@ready_callback = block
		@ready_callback.yield if @ready
	end

	def on_disconnect(&block)
		@unbind_callback = block
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
					@ready_callback.yield if @ready_callback
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
		@unbind_callback.yield if @unbind_callback

		@node.del_conn(self)

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

	def method_allowed?(obj, fn)
		obj.respond_to?(fn) and obj.class.class_variable_defined?(:@@_pwr_exposed) and
			obj.class.class_variable_get(:@@_pwr_exposed).class == Array and
			obj.class.class_variable_get(:@@_pwr_exposed).include?(fn)
	end

	def handle_request(msgid, ref, fn, params)
		$logger.info("Incoming req.: <#{msgid}> #{ref}.#{fn}(#{params.inspect[1..-2]})")
		if obj = @node.obj(ref)
			if method_allowed?(obj, fn) or obj.class == PwrObj
				Fiber.new{
					obj.instance_variable_set(:@pwrcall_current_connection, self)
					begin
						if method_allowed?(obj, fn)
							send_response(msgid, obj.send(fn, *params))
						elsif obj.class == PwrObj
							### We should not use obj.send() here because this will also call
							### methods of parent classes (including the eval method!)
							send_response(msgid, obj.method_missing(fn, *params))
						else
							$logger.fatal("Something went wrong.")
							unbind()
							return
						end
					rescue => errormsg
						send_error(msgid, errormsg.inspect)
					end
				}.resume
			else
				send_error(msgid, "#{ref}.#{fn}() does not exist")
			end
		else
			send_error(msgid, "#{ref} does not exist")
		end
	end

	def handle_response(msgid, error, result)
		if @pending[msgid] == nil
			$logger.error("Incoming response with invalid msgid #{msgid}")
			return
		end
		if error
			$logger.warn("Incoming err.: <#{msgid}> #{[error, result].inspect}")
			@pending[msgid].set_error(error)
		else
			$logger.info("Incoming res.: <#{msgid}> #{result.inspect}")
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
		$logger.info("Outgoing err.: <#{msgid}> #{error.inspect}")
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
	def initialize(conn=nil, *args)
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

	def get_peer()
		Socket.unpack_sockaddr_in(get_peername)
	end

	######

	private

	def print_connected_msg()
		@peer = get_peer()
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
