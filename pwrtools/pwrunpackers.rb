#!/usr/bin/env ruby
# more requires at the bottom
require File.dirname(__FILE__) + '/pwrlogger.rb'

class PwrUnpacker
	@@unpackers = {}
	def initialize()
		@ready = []
	end

	def next()
		@ready.shift
	end

	def feed(data) end
	def pack(data) end
	def unpack(data) end

	def self.unpackers()
		return @@unpackers
	end

	def self.add_unpacker(key, classname)
		@@unpackers[key] = classname
	end
end

class PwrJSON < PwrUnpacker
	def initialize()
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

	def unpack(data)
		begin
			return JSON.deserialize(data)
		rescue JSON::ParserError
			$logger.warn("JSON error: Failed to parse #{data.inspect}")
		end
		return nil
	end

	def pack(data)
		data.map{ |d| d.class == String ? d.force_encoding('ISO-8859-1') : d }.to_json
	end

	private
	def parse_complete(json)
		@ready.push(json)
		$logger.debug("JSON parsed: " + json.inspect)
	end
end

class PwrMessagePack < PwrUnpacker
	def initialize()
		@parser = MessagePack::Unpacker.new()
		super
	end

	def feed(data)
		@parser.feed(data)
		@parser.each do |obj|
			@ready.push(obj)
		end
	end

	def unpack(data)
		MessagePack::unpack(data)
	end

	def pack(data)
		MessagePack::pack(data)
	end
end

class PwrBSON < PwrUnpacker
	def initialize()
		@buf = ""
		super
	end

	def feed(data)
		@buf += data
		while @buf.length > 4
			len = @buf[0,4].unpack("l<")[0] # int32_t little endian
			break if @buf.length < len
			blob = @buf[0,len]
			@buf = @buf[len..-1] || ""
			blob = unpack(blob)
			if blob and blob['data']
				@ready.push(blob['data'])
				$logger.debug("BSON parsed: " + blob.inspect)
			else
				$logger.warn("BSON error: parsed hash does not contain data field")
			end
		end
	end

	def unpack(data)
		begin
			data = BSON.deserialize(data)
			data.each do |k,v|
				if v.class == BSON::Binary then
					data[k] = v.to_s
				end
			end
			return data
		rescue TypeError
			$logger.warn("BSON error: Failed to parse #{data.inspect}")
		end
		return nil
	end

	def pack(data, binary=false)
		if binary and data.class == Hash
			data = data.dup
			data.each do |k,v|
				if v.class == String then
					data[k] = BSON::Binary.new(v)
				end
			end
		else
			data = { data: data }
		end
		return BSON.serialize(data).to_s
	end

	def pack_binary(data)
		pack(data, true)
	end
end

begin
	require 'yajl'
	require 'json'
	PwrUnpacker.add_unpacker('json', PwrJSON)
rescue LoadError
	$logger.debug("No JSON support :-(")
end

begin
	require 'msgpack'
	PwrUnpacker.add_unpacker('msgpack', PwrMessagePack)
rescue LoadError
	$logger.debug("No MessagePack support :-(")
end

begin
	require 'bson'
	PwrUnpacker.add_unpacker('bson', PwrBSON)
rescue LoadError
	$logger.debug("No BSON support :-(")
end
