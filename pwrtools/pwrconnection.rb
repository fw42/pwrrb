#!/usr/bin/env/ruby

### Subclass this!
class PwrConnection
	def initialize()
		@fiber = Fiber.current
	end

	def set_connection_handler(handler)
		@connection_handler = handler
	end

	def send(data)
		@connection_handler.send(data)
	end

	###### Callbacks

	### On incoming data
	def receive_data(data)
		$logger.warn("receive_data() not implemented")
	end

	### On successful connection establishment
	def connection_established(*args)
	end

	### On connection termination
	def unbind()
	end
end
