#!/usr/bin/env ruby
# http://www.simulacre.org/unblocking-readline-in-eventmachine/
require 'fiber'
require 'eventmachine'

module NonblockingKeyboard
	def post_init
		@ostdin = $stdin
		$stdin  = self
		@buffer = ""
	end

	def receive_data(d)
		@buffer << d
		@waiting && @waiting[:cnt] <= @buffer.length && @waiting[:fiber].resume
	end

	def read(cnt)
		if @buffer.length < cnt
			@waiting = {:cnt => cnt, :fiber => Fiber.current}
			Fiber.yield
		end
		data, @buffer = @buffer[0...cnt], @buffer[cnt..-1]
		@buffer = "" unless @buffer
		data
  end

	def unbind
		$stdin = @ostdin
	end

	def method_missing(meth, *args, &blk)
		@ostdin.send(meth, *args, &blk)
	end
end
