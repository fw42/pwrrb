#!/usr/bin/env ruby
require 'rb-readline'
require 'pry'
require File.expand_path("../pwrcall.rb", __FILE__)
require File.expand_path("../../pwrtools/nonblocking_keyboard.rb", __FILE__)

Pwr.run do
	PwrFiber.new{
		EM.open_keyboard(NonblockingKeyboard) do |kb|
			node = PwrNode.new()
			example_url = "pwrcall://21bc7f3c3956e5aa04a6dc33fea9d2b913b4157c@localhost:10001/foobar"
			Pry.prompt = [
				proc { |obj, nest_level| "pwr> " },
				proc { |obj, nest_level| "pwr> " }
			]
			binding.pry({ :quiet => true })
		end
	}.resume().wait()
	Pwr.stop()
end
