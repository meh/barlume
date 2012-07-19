#! /usr/bin/env ruby
require 'barlume'
require 'socket'

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
			puts lucciola.readline rescue nil

			if lucciola.closed?
				clients.delete(lantern.remove(lucciola))
			end
		end
	}
end
