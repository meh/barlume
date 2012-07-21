#! /usr/bin/env ruby
require 'socket'
require 'thread'

2.times.map {
	Thread.new {
		sockets = []

		100.times {
			sockets << TCPSocket.new('localhost', 43215)
		}

		sockets.each {|socket|
			socket.puts 'a' * 4096
		}
	}
}.each(&:join)
