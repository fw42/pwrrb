#!/usr/bin/env ruby
require 'yajl'
require 'json'
require 'bson'

class PwrUnpacker
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
		{ 'json' => PwrJSON, 'bson' => PwrBSON }
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
			return BSON.deserialize(data)
		rescue TypeError
			$logger.warn("BSON error: Failed to parse #{blob.inspect}")
		end
		return nil
	end

	def pack(data)
		BSON.serialize({ data: data }).to_s
	end
end
