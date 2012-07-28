#! /usr/bin/env ruby
require 'rubygems'
require 'barlume'

GC.disable

lanterna = Barlume::Lanterna.poll
server   = lanterna.add(TCPServer.new(1337)).asynchronous!.readable!
server.listen(1024)

puts "Using #{lanterna.name}..."

loop do
	lanterna.available {|event, lucciola|
		if event == :error
			lucciola.delete!.close rescue nil
		elsif event == :readable
			begin
				if lucciola == server
					while client = lucciola.accept
						lanterna.add(client).asynchronous!.readable!
					end
				else
					begin
						lucciola.write lucciola.read(2048)
					rescue EOFError, Errno::ECONNRESET
						lucciola.delete!.close
					end
				end
			rescue Errno::EAGAIN; end
		end
	}
end
