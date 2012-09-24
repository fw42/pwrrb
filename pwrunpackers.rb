#!/usr/bin/ruby1.9.1
require 'yajl'
require 'json'
require 'bson'

class PwrUnpacker
	def initialize
		@ready = []
	end

	def next
		@ready.shift
	end

	def feed(data) end
	def pack() end

	def self.unpackers()
		{ 'json' => PwrJSON, 'bson' => PwrBSON }
	end
end

class PwrJSON < PwrUnpacker
	def initialize
		@parser = Yajl::Parser.new
		@parser.on_parse_complete = method(:parse_complete)
		@ready = []
		super
	end

	def feed(data)
		begin
			@parser << data
		rescue Yajl::ParseError
			$logger.warn("JSON parsing error: #{data.inspect}")
		end
	end

	def pack(data)
		data.map{ |d| d.class == String ? d.force_encoding('ISO-8859-1') : d }.to_json
	end

	private
	def parse_complete(json)
		@ready.push(json)
	end
end

class PwrBSON < PwrUnpacker
	def initialize
		@buf = ""
		super
	end

	def feed(data)
		@buf += data
		while @buf.length > 4
			len = @buf[0,4].unpack("N")[0]
			break if @buf.length < len
			blob = @buf[4,len-4]
			@buf = @buf[len..-1] || ""
			begin
				blob = BSON.deserialize(blob)
				@ready.push(blob['data']) if blob['data']
			rescue TypeError
				$logger.warn("BSON parsing error: #{blob.inspect}")
			end
		end
	end

	def pack(data)
#		puts [ data.length, [data.length].pack("N"), data ].inspect
		bson = BSON.serialize({ data: data }).to_s
		[4+bson.length].pack("N") + bson
	end
end
