#! /usr/bin/env ruby
# encoding: utf-8
require 'rubygems'
require 'barlume'
require 'optparse'

options = {}

OptionParser.new do |o|
  options[:host]    = 'localhost'
  options[:port]    = 4567
  options[:threads] = 16
  options[:content] = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
  options[:sleep]    = 1

  o.on '-h', '--host host', 'the host of the server' do |value|
    options[:host] = value
  end

  o.on '-p', '--port port', Integer, 'the port of the server' do |value|
    options[:port] = value
  end

  o.on '-t', '--threads [MAX_THREADS]', 'the max amount of threads on the server' do |value|
    options[:threads] = value
  end

  o.on '-c', '--content CONTENT', 'the string to send' do |value|
    options[:content] = value
  end

  o.on '-s', '--sleep SECONDS', Float, 'the time to sleep before sending every character' do |value|
    options[:sleep] = value
  end
end.parse!

class Slowpoke < Barlume::Lucciola
  def initialize (socket, message)
    super(socket)

    @message = message
    @offset  = 0
  end

  def send_next
    return if done?

    write_nonblock @message[@offset]

    @offset += 1
  rescue Errno::EAGAIN, Errno::EWOULDBLOCK
  end

  def done?
    @offset >= @message.length
  end
end

lantern = Barlume::Lanterna.best

options[:threads].times {
  lantern << Slowpoke.new(TCPSocket.new(options[:host], options[:port]), options[:content])
}

puts "oh noes, a wall on my path D:"

until lantern.descriptors.all?(&:done?)
  lantern.writable.each {|s|
    s.send_next
  }

  sleep options[:sleep]
end

puts "oh, there's a door ( ･ ◡◡･)"
