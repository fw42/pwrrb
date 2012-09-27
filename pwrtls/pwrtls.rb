#!/usr/bin/env/ruby
require File.dirname(__FILE__) + '/../pwr.rb'
require 'nacl'
require 'bson'

class PwrTLS
	def self.connect(server, port, conn)
		EventMachine::connect(server, port, PwrConnectionHandlerPwrTLS, conn)
		return Fiber.yield ? conn : nil
	end

	def self.listen(server, port, conn, &block)
		# TODO
	end
end

module PwrConnectionHandlerPwrTLS
	def initialize(conn=nil)
		set_connection(conn)
		@packer = PwrBSON.new()
		@buf = ""
		@state = :new
		@peer = { snonce: 0 }
		@server = (conn == nil)

		### Short-term keypair and fresh nonce
		@me = { snonce: 1 }
		@me[:spk], @me[:ssk] = NaCl.crypto_box_keypair()

		### TODO: load this from file
		@me[:lpk], @me[:lsk] = NaCl.crypto_box_keypair()
		@me[:lnonce] = 1
	end

	###### Interface to PwrConnection

	public

	def set_connection(conn)
		@conn = conn
		@conn.set_connection_handler(self) if conn
	end

	def send(data)
		send_framed(NaCl.crypto_box(data, snonce_my_next(), @peer[:spk], @me[:ssk]))
	end

	######

	private

	def print_connected_msg()
		@peer[:port], @peer[:ip] = Socket.unpack_sockaddr_in(get_peername)
		$logger.info("TCP connection with #{@peer[:ip]}:#{@peer[:port]} established")
	end

	###### Callbacks

	public

	def receive_data(data)
		$logger.debug("PwrTLS<< " + data.inspect)
		@buf << data
		while @buf.length > 4
			len = @buf[0,4].unpack("N")[0]
			break if len > @buf.length
			packet = @buf[4,(len-4)]
			@buf = @buf[len..-1] || ""
			handle_packet(packet)
		end
	end

	def connection_completed()
		print_connected_msg()
		send_client_hello()
	end

	def server_accepted()
		print_connected_msg()
	end

	def unbind()
		@conn.unbind()
		$logger.info("PwrTLS connection with #{@peer[:ip]}:#{@peer[:port]} closed") if @peer[:ip]
	end

	######

	private

	def snonce_my_next()
		@me[:snonce] += 2
		return snonce(@me[:snonce])
	end

	def snonce_peer_next()
		@peer[:snonce] += 2
		return snonce(@peer[:snonce])
	end

	def snonce(num)
		"pwrnonceshortXXX" + [ num ].pack("Q")
	end

	def lnonce(num)
		"pwrnonce" + [ num, 2**47 + rand(2**47) ].pack("QQ")
	end

	def handle_packet(packet)
		if @state != :ready
			packet = @packer.unpack(packet)
		end

		if @server and @state == :new

			

		elsif !@server and @state == :client_hello_sent

			if !packet['lpub'] or !packet['box']
				$logger.error("Received SERVER HELLO without lpub or box")
				return
			end

			@peer[:lpk] = packet['lpub'].to_s
			payload = @packer.unpack(decrypt(packet['box'].to_s, snonce_peer_next(), @peer[:lpk], @me[:ssk]))
			@peer[:spk] = payload['spub'].to_s

			$logger.info("Received SERVER HELLO from #{@peer[:ip]}:#{@peer[:port]}")
			send_client_verify()
			$logger.info("Handshake with #{@peer[:ip]}:#{@peer[:port]} complete")

			@state = :ready
			$logger.info("PwrTLS connection with #{@peer[:ip]}:#{@peer[:port]} established")

			@conn.connection_established()

		elsif @state == :ready
			@conn.receive_data(decrypt(packet, snonce_peer_next(), @peer[:spk], @me[:ssk]))
		else
			$logger.warn("Received unexpected packet!")
			return
		end
	end

	######

	def decrypt(ciphertext, nonce, pk, sk)
		begin
			return NaCl.crypto_box_open(ciphertext, nonce, pk, sk)
		rescue NaCl::OpenError
			$logger.error("Decryption error!")
			# TODO: disconect
		end
	end

	######

	private

	def send_client_hello()
		send_framed(@packer.pack_binary({ spub: @me[:spk] }))
		$logger.info("Sent CLIENT HELLO to #{@peer[:ip]}:#{@peer[:port]}")
		@state = :client_hello_sent
	end

	def send_client_verify()
		vn = lnonce(@me[:lnonce])
		vbox = NaCl.crypto_box(@me[:spk], vn, @peer[:lpk], @me[:lsk])
		verifybox = NaCl.crypto_box(
			@packer.pack_binary({ lpub: @me[:lpk], v: vbox, vn: vn }).to_s,
			snonce_my_next(), @peer[:spk], @me[:ssk]
		)
		$logger.info("Sent CLIENT VERIFY to #{@peer[:ip]}:#{@peer[:port]}")
		send_framed(verifybox)
	end

	def send_framed(data)
		send_raw([data.length+4].pack("N") + data)
	end

	def send_raw(data)
		$logger.debug("PwrTLS>> " + data.inspect)
		send_data(data)
	end
end
