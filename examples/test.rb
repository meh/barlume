#! /usr/bin/env ruby
require 'barlume'
require 'socket'

lantern = Barlume::Lanterna.poll
server  = TCPServer.new 43215
clients = []

lantern.add(server)

loop do
	lantern.readable.each {|lucciola|
		if lucciola == server
			server.accept.tap {|client|
				clients.push(lantern.add(client))
			}
		else
			puts lucciola.readline rescue nil

			if lucciola.closed?
				clients.remove(lantern.remove(lucciola))
			end
		end
	}
end
