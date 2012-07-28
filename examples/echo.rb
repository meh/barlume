#! /usr/bin/env ruby
require 'rubygems'
require 'barlume'

class Echo < Barlume::Lucciola
	CHUNK_SIZE = 2048

	def initialize (*)
		super
		
		@buffer = ''
	end

	def read_all
		while chunk = read(CHUNK_SIZE)
			@buffer << chunk
		end
	rescue Errno::EAGAIN; end

	def write_all
		while @buffer.length > 0
			if @buffer.length <= CHUNK_SIZE
				written = write @buffer

				if written < @buffer.length
					@buffer[0, written] = ''

					return false
				else
					@buffer.clear
				end
			else
				written = write @buffer[0, CHUNK_SIZE]

				@buffer[0, written] = ''

				if written < CHUNK_SIZE
					return false
				end
			end
		end

		true
	rescue Errno::EAGAIN
		false
	end
end

lanterna = Barlume::Lanterna.best
server   = lanterna.add(TCPServer.new(1337)).asynchronous!.readable!
server.listen(1024)

puts "Using #{lanterna.name}..."

loop do
	lanterna.available {|event, lucciola|
		if event == :error
			lucciola.delete!.close rescue nil
		elsif event == :readable
			if lucciola == server
				while client = lucciola.accept rescue nil
					lanterna.add(Echo.new(client)).asynchronous!.readable!
				end
			else
				begin
					lucciola.read_all
					lucciola.writable!
				rescue EOFError, Errno::ECONNRESET
					lucciola.delete!
				end
			end
		elsif event == :writable
			if lucciola.write_all
				lucciola.no_writable!
			end
		end
	}
end
