#! /usr/bin/env ruby
require 'barlume'

lantern = Barlume::Lanterna.best
server  = lantern.add(TCPServer.new(43215))
bytes   = 0
clients = 0

puts "Using #{lantern.name}..."

trap 'INT' do
	puts "Received #{bytes} bytes from #{clients} clients"
	exit!
end

loop do
	lantern.readable.each {|lucciola|
		if lucciola == server
			while client = server.accept_nonblock rescue nil
				clients += 1
				lantern.add(client)
			end
		else
			begin
				while value = lucciola.read(2048)
					bytes += value.bytesize
				end
			rescue EOFError, Errno::EAGAIN; end

			if lucciola.closed?
				lantern.remove(lucciola)
			end
		end
	}
end
