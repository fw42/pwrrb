#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../../pwrtools/pwrconnection.rb'

class ChatExample < PwrConnection
	def receive_data(data)
		puts data
	end
end
