#! /usr/bin/env ruby
require 'rubygems'
require 'barlume'

lanterna = Barlume::Lanterna.select
server   = lanterna.add(TCPServer.new(43215)).asynchronous!.readable!

puts "Using #{lanterna.name}..."

class Echo < Barlume::Lucciola
	CHUNK_SIZE = 2048

	def initialize (*)
		super
		
		@buffer = ''
	end

	def received (buffer)
		@buffer << buffer

		self
	end

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

loop do
	readable, writable, error, timeout = lanterna.available.to_a

	readable.each {|lucciola|
		if lucciola == server
			while client = lucciola.accept rescue nil
				lanterna.add(Echo.new(client)).asynchronous!.readable!
			end
		else
			buffer = ''

			begin
				buffer << lucciola.read(2048)
			rescue EOFError, Errno::EAGAIN; end

			if lucciola.closed?
				lanterna.remove(lucciola)
			else
				lucciola.received(buffer).writable!
			end
		end
	}

	writable.each {|echo|
		if echo.write_all
			echo.no_writable!
		end
	}
end
