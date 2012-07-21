#! /usr/bin/env ruby
require 'rubygems'
require 'barlume'

lantern = Barlume::Lanterna.best
server  = lantern.add(TCPServer.new(43215))

puts "Using #{lantern.name}..."

loop do
	lantern.readable.each {|lucciola|
		if lucciola == server
			server.accept.tap {|client|
				lantern.add(client)
			}
		else
			begin
				puts lucciola.read(2048)
			rescue EOFError; end

			if lucciola.closed?
				lantern.remove(lucciola)
			end
		end
	}
end
