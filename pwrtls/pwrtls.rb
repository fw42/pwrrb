#!/usr/bin/env/ruby
require File.expand_path("../../pwr.rb", __FILE__)
require 'nacl'

class PwrTLS
	def self.connect(server, port, conn)
		EventMachine::connect(server, port, PwrConnectionHandlerPwrTLS, conn)
		return Fiber.yield ? conn : nil
	end

	def self.listen(server, port, connclass, &block)
		EventMachine::start_server(server, port, PwrConnectionHandlerPwrTLS) do |c|
			conn = connclass.new()
			c.set_connection(conn)
			c.server_accepted()
			block.yield(connclass)
		end
		$logger.info("Listening on #{server}:#{port}")
	end

	def self.keypair_init(filename=nil)
		packer = PwrBSON.new()
		pk, sk = NaCl.crypto_box_keypair
		data = { "pubkey" => pk, "privkey" => sk, "nonce" => 1 }
		if filename
			f = File.open(filename, "wb")
			f.write packer.pack_binary(data)
			f.close
		end
		return data
	end

	def self.keypair_load(filename)
		packer = PwrBSON.new()
		data = File.read(filename)
		return packer.unpack(data)
	end

	def self.key_fingerprint(key)
		Digest::SHA1.hexdigest(key)
	end
end

module PwrConnectionHandlerPwrTLS
	def initialize(conn=nil, keypair=nil, fingerprint=nil)
		set_connection(conn)

		if !PwrUnpacker.unpackers['bson'] then
			$logger.fatal("PwrTLS requires BSON :-(")
			exit
		end
		@packer = PwrBSON.new()

		@buf = ""
		@state = :new
		@peer = {}
		@me = {}

		if fingerprint
			@peer[:fingerprint] = fingerprint.downcase
		end

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

		### Long-term keypair and nonce
		if !keypair
			keypair = PwrTLS.keypair_init()
		end
		@me[:lpk] = keypair["pubkey"]
		@me[:lsk] = keypair["privkey"]
		@me[:lnonce] = keypair["nonce"]

		$logger.info("Using public-key with fingerprint #{PwrTLS.key_fingerprint(@me[:lpk])}")
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

	def get_peer()
		[ @peer[:port], @peer[:ip] ]
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
		@conn.unbind() if @conn
		if @peer[:ip]
			if @state == :ready
				$logger.info("PwrTLS connection with #{@peer[:ip]}:#{@peer[:port]} closed")
			end
			$logger.info("TCP connection with #{@peer[:ip]}:#{@peer[:port]} closed")
		end
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

	def lnonce_my_next()
		@me[:lnonce] += 2
		return lnonce(@me[:lnonce])
	end

	def snonce(num)
		"pwrnonceshortXXX" + [ num ].pack("Q")
	end

	def lnonce(num)
		"pwrnonce" + [ num, 2**47 + rand(2**47) ].pack("QQ")
	end

	def handle_packet(packet)
		packet = @packer.unpack(packet) unless @state == :ready or @state == :server_hello_sent
		if @server and @state == :new
			if !packet['spub']
				$logger.fatal("Received invalid CLIENT HELLO")
				unbind()
				return
			end
			@peer[:spk] = packet['spub']
			$logger.info("Received CLIENT HELLO from #{@peer[:ip]}:#{@peer[:port]}")
			send_server_hello()
			@state = :server_hello_sent
		elsif @server and @state == :server_hello_sent
			### Client verify
			if (payload = decrypt(packet, snonce_peer_next(), @peer[:spk], @me[:ssk])) == nil
				unbind()
				return
			end
			payload = @packer.unpack(payload)
			if !payload['lpub'] or !payload['v'] or !payload['vn']
				$logger.fatal("Received invalid CLIENT VERIFY")
				unbind()
				return
			end
			@peer[:lpk] = payload['lpub']
			@peer[:spk] = decrypt(payload['v'], payload['vn'], @peer[:lpk], @me[:lsk])
			if @peer[:spk] == nil
				unbind()
				return
			end
			$logger.info("Received CLIENT VERIFY from #{@peer[:ip]}:#{@peer[:port]}")
			fp = PwrTLS.key_fingerprint(@peer[:lpk]).downcase
			$logger.warn("Client not authenticated! Fingerprint #{fp} not known.") # TODO
			handshake_complete()
		elsif !@server and @state == :client_hello_sent
			if !packet['lpub'] or !packet['box']
				$logger.fatal("Received incomplete SERVER HELLO")
				unbind()
				return
			end
			@peer[:lpk] = packet['lpub']
			if @peer[:fingerprint]
				fp = PwrTLS.key_fingerprint(@peer[:lpk]).downcase
				if fp != @peer[:fingerprint]
					$logger.fatal("Server public-key fingerprint does not match expected fingerprint!")
					$logger.fatal("#{fp} != #{@peer[:fingerprint]}")
					unbind()
					return
				else
					$logger.info("Server public-key with fingerprint #{fp} okay.")
				end
			else
				$logger.warn("Server is not authenticated! No fingerprint known!")
			end
			payload = decrypt(packet['box'], snonce_peer_next(), @peer[:lpk], @me[:ssk])
			if payload == nil
				unbind()
				return
			end
			payload = @packer.unpack(payload)
			if !payload['spub']
				$logger.fatal("Received invalid SERVER HELLO")
				unbind()
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
			$logger.error("Decryption error")
			return nil
		end
	end

	def encrypt(plaintext, nonce, pk, sk)
		begin
			return NaCl.crypto_box(plaintext, nonce, pk, sk)
		rescue ArgumentError => error
			$logger.error("Encryption error: " + error.to_s)
			return nil
		end
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
		vn = lnonce_my_next()
		send_unencrypted(
			encrypt(@packer.pack_binary({
				lpub: @me[:lpk], v: encrypt(@me[:spk], vn, @peer[:lpk], @me[:lsk]), vn: vn
			}), snonce_my_next(), @peer[:spk], @me[:ssk])
		)
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
