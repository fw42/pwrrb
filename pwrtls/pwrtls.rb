#!/usr/bin/env/ruby
require 'eventmachine'
require 'nacl'
require 'bson'
require './logger'
require './pwrunpackers.rb'

module PwrTLS
	def initialize()
		@state = :new
		@me = {}
		@me[:spk], @me[:ssk] = NaCl.crypto_box_keypair()
		@me[:lpk], @me[:lsk] = NaCl.crypto_box_keypair()
		@me[:nonce] = 1
		@peer = { :nonce => 4 }
		@packer = PwrBSON.new()
		@buf = ""
	end

	def connection_completed
		connection_established()
		send_client_hello()
	end

	def unbind
		$logger.info("Connection with #{@peer[:ip]}:#{@peer[:port]} closed") if @peer[:ip]
	end

	def receive_data(data)
		$logger.debug("<< " + data.inspect)
		@buf << data
		while @buf.length > 4
			len = @buf[0,4].unpack("N")[0]
			break if len > @buf.length
			packet = @buf[4,(len-4)]
			@buf = @buf[len..-1] || ""
			handle_packet(packet)
		end
	end

	######

	def connection_established
		@peer[:port], @peer[:ip] = Socket.unpack_sockaddr_in(get_peername)
		$logger.info("Connection with #{@peer[:ip]}:#{@peer[:port]} established")
	end

	def next_snonce()
		@me[:nonce] += 2
		return snonce(@me[:nonce])
	end

	def snonce(num)
		"pwrnonceshortXXX" + [ num ].pack("Q")
	end

	def lnonce()
		"pwrnonce" + [ num, 2**47 + rand(2**47) ].pack("QQ")
	end

	def handle_packet(packet)
		if @state != :ready
			packet = @packer.unpack(packet)
		end

		if @state == :client_hello_sent
			if !packet['lpub'] or !packet['box']
				$logger.error("Received SERVER HELLO without lpub or box")
				return
			end

			@peer[:lpk] = packet['lpub'].to_s
			begin
				payload = @packer.unpack(NaCl.crypto_box_open(packet['box'].to_s, snonce(2), @peer[:lpk], @me[:ssk]))
			rescue NaCl::OpenError
				$logger.error("Decryption error!")
				# TODO: disconect
			end

			$logger.info("Received SERVER HELLO from #{@peer[:ip]}:#{@peer[:port]}")

			vn = lnonce()
			@peer[:spk] = payload['spub'].to_s
			vbox = NaCl.crypto_box(@me[:spk], vn, @peer[:lpk], @me[:lsk])
			verifybox = NaCl.crypto_box(
				@packer.pack_binary({ lpub: @me[:lpk], v: vbox, vn: vn }).to_s,
				next_snonce(), @peer[:spk], @me[:ssk]
			)
			$logger.info("Sent CLIENT VERIFY to #{@peer[:ip]}:#{@peer[:port]}")
			send_framed(verifybox)

			@state = :ready
		elsif @state == :ready
			begin
				payload = NaCl.crypto_box_open(packet, snonce(@peer[:nonce]), @peer[:spk], @me[:ssk])
				@peer[:nonce] += 2
				$logger.debug("<< Got payload: " + payload.inspect)
			rescue NaCl::OpenError
				$logger.error("Decryption error!")
				# TODO: disconnect
			end
		end
	end

	######

	def send_client_hello()
		$logger.info("Sent CLIENT HELLO to #{@peer[:ip]}:#{@peer[:port]}")
		send_framed(@packer.pack_binary({ spub: @me[:spk] }))
		@state = :client_hello_sent
	end

	def send_framed(data)
		send([data.length+4].pack("N") + data)
	end

	def send(data)
		$logger.debug(">> " + data.inspect)
		send_data(data)
	end
end
