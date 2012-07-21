#! /usr/bin/env ruby
require 'rubygems'
require 'barlume'

lantern = Barlume::Lanterna.best
server  = TCPServer.new 43215
clients = []

puts "Using #{lantern.name}..."

lantern << server

loop do
	lantern.readable.each {|lucciola|
		if lucciola == server
			server.accept.tap {|client|
				clients.push(lantern.add(client))
			}
		else
			begin
				puts lucciola.read(2048)
			rescue EOFError; end

			if lucciola.closed?
				clients.delete(lantern.remove(lucciola))
			end
		end
	}
end
