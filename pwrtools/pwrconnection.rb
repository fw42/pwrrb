#!/usr/bin/env/ruby

### Subclass this!
class PwrConnection
	def initialize()
	end

	def set_connection_handler(handler)
		@connection_handler = handler
	end

	def send(data)
		@conn.send(data)
	end

	###### Callbacks

	### On incoming data
	def receive_data(data)
	end

	### On successful connection establishment (client)
	def connection_completed(*args)
	end

	### On connection termination
	def unbind()
	end
end
