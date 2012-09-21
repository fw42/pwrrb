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
		{ 'json' => PwrJSON }
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
		@parser << data
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
	def initliaze
		@buf = ""
	end

	def feed(data)
		@buf += data
		while @buf.length > 4
			len = @buf[0,4].unpack("N")
			break if @buf.length < len
			blob = @buf[4,len-4]
			@buf = @buf[len..-1] || ""
			bson = BSON.deserialize(@buf.unpack("C"))
			@ready.push(bson)
		end
	end

	def pack(data)
		[4+data.length].pack("N") + BSON.serialize(data).to_s
	end
end
