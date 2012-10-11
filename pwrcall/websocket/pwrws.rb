#!/usr/bin/env ruby
require File.expand_path("../../pwrcall.rb", __FILE__)

require 'rack/file'
require File.expand_path('../lib/faye/websocket', __FILE__)
Faye::WebSocket.load_adapter("thin")

class WebRequestHandler
	def initialize(node)
		@static = Rack::File.new(File.dirname(__FILE__) + "/static")
		@node = node
	end

	def request(env)
		if Faye::WebSocket.websocket?(env)
			ws = Faye::WebSocket.new(env)
			pwrconn = PwrCallConnection.new(@node, nil, true)
			pwr = PwrConnectionHandlerWebSocket.new(ws, pwrconn)
			ws.rack_response
		else
			['REQUEST_PATH', 'REQUEST_URI', 'PATH_INFO'].each do |key|
				env[key] = "index.html" if env[key] == "/"
			end
			@static.call(env)
		end
	end
end

class PwrConnectionHandlerWebSocket
	def initialize(sock, conn=nil)
		@sock = sock
		sock.onmessage = method(:receive_data)
		sock.onclose = method(:unbind)
		sock.onopen = method(:connection_completed)
		set_connection(conn)
	end

	###### Interface to PwrConnection

	public

	def set_connection(conn)
		@conn = conn
		@conn.set_connection_handler(self) if conn
	end

	def send(data)
		@sock.send(data)
	end

	######

	private

	def print_connected_msg()
		@peer = get_peer()
		$logger.info("WebSocket connection with #{@peer[1]}:#{@peer[0]} established") if @peer
	end

	###### Callbacks

	public

	def get_peer
		[ @sock.env['REMOTE_PORT'], @sock.env['REMOTE_ADDR'] ]
	end

	def receive_data(event)
		@conn.receive_data(event.data)
	end

	def connection_completed(event)
		print_connected_msg()
		@conn.connection_established()
	end

	def server_accepted()
		print_connected_msg()
		@conn.connection_established()
	end

	def unbind(event)
		@conn.unbind() if @conn
		if @peer
			$logger.info("WebSocket connection with #{@peer[1]}:#{@peer[0]} closed")
		end
	end
end
