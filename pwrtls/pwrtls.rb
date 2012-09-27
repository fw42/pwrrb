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
		@peer = {}
		@me = {}

		### Client sends the first message
		if @server = (conn == nil)
			@peer[:snonce] = 1
			@me[:snonce] = 0
		else
			@peer[:snonce] = 0
			@me[:snonce] = 1
		end

		### Short-term keypair
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
		send_encrypted(data)
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
		@state = :client_hello_sent
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
		packet = @packer.unpack(packet) unless @state == :ready
		if @server and @state == :new
			if !packet['spub']
				$logger.error("Received invalid CLIENT HELLO")
				return
			end
			@peer[:spk] = packet['spub']
			$logger.info("Received CLIENT HELLO from #{@peer[:ip]}:#{@peer[:port]}")
			send_server_hello()
			@state = :server_hello_sent
		elsif @server and @state == :server_hello_sent
			if !packet['box'] then
				$logger.error("Received invalid CLIENT VERIFY")
				return
			end
			payload = @packer.unpack(decrypt(packet['box'], snonce_peer_next(), @peer[:spk], @me[:ssk]))
			if !payload['lpub'] or !payload['v'] or !payload['vn']
				$logger.error("Received invalid CLIENT VERIFY")
				return
			end
			@peer[:lpk] = payload['lpub']
			@peer[:spk] = decrypt(payload['v'], payload['vn'], @peer[:lpk], @me[:lsk])
			$logger.info("Received CLIENT VERIFY from #{@peer[:ip]}:#{@peer[:port]}")
			$logger.error("TODO: verification!") # TODO: verification
			handshake_complete()
		elsif !@server and @state == :client_hello_sent
			if !packet['lpub'] or !packet['box']
				$logger.error("Received incomplete SERVER HELLO")
				return
			end
			@peer[:lpk] = packet['lpub']
			payload = @packer.unpack(decrypt(packet['box'], snonce_peer_next(), @peer[:lpk], @me[:ssk]))
			if !payload['spub']
				$logger.error("Received invalid SERVER HELLO")
				return
			end
			@peer[:spk] = payload['spub']
			$logger.info("Received SERVER HELLO from #{@peer[:ip]}:#{@peer[:port]}")
			send_client_verify()
			handshake_complete()
		elsif @state == :ready
			@conn.receive_data(decrypt(packet, snonce_peer_next(), @peer[:spk], @me[:ssk]))
		else
			$logger.warn("Received unexpected packet in state #{@state}")
			return
		end
	end

	######

	private

	def decrypt(ciphertext, nonce, pk, sk)
		begin
			return NaCl.crypto_box_open(ciphertext, nonce, pk, sk)
		rescue NaCl::OpenError
			$logger.error("Decryption error!")
			unbind()
		end
	end

	def encrypt(plaintext, nonce, pk, sk)
		NaCl.crypto_box(plaintext, nonce, pk, sk)
	end

	def handshake_complete()
		$logger.info("Handshake with #{@peer[:ip]}:#{@peer[:port]} complete")
		@state = :ready
		$logger.info("PwrTLS connection with #{@peer[:ip]}:#{@peer[:port]} established")
		@conn.connection_established()
	end

	######

	private

	def send_encrypted(data)
		send_framed(encrypt(data, snonce_my_next(), @peer[:spk], @me[:ssk]))
	end

	def send_unencrypted(data)
		send_framed(data)
	end

	def send_server_hello()
		send_unencrypted(@packer.pack_binary({
			lpub: @me[:lpk],
			box: encrypt(
				@packer.pack_binary({ spub: @me[:spk] }),
				snonce_my_next(), @peer[:spk], @me[:lsk]
			)
		}))
		$logger.info("Sent SERVER HELLO to #{@peer[:ip]}:#{@peer[:port]}")
	end

	def send_client_hello()
		send_unencrypted(@packer.pack_binary({ spub: @me[:spk] }))
		$logger.info("Sent CLIENT HELLO to #{@peer[:ip]}:#{@peer[:port]}")
	end

	def send_client_verify()
		vn = lnonce(@me[:lnonce])
		send_unencrypted(@packer.pack_binary({
			box: encrypt(@packer.pack_binary({
				lpub: @me[:lpk], v: encrypt(@me[:spk], vn, @peer[:lpk], @me[:lsk]), vn: vn
			}), snonce_my_next(), @peer[:spk], @me[:ssk])
		}))
		$logger.info("Sent CLIENT VERIFY to #{@peer[:ip]}:#{@peer[:port]}")
	end

	def send_framed(data)
		send_raw([data.length+4].pack("N") + data)
	end

	def send_raw(data)
		$logger.debug("PwrTLS>> " + data.inspect)
		send_data(data)
	end
end
