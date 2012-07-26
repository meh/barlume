#--
# Copyleft meh. [http://meh.paranoid.pk | meh@paranoici.org]
#
# This file is part of barlume.
#
# barlume is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# barlume is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with barlume. If not, see <http://www.gnu.org/licenses/>.
#++

require 'fcntl'
require 'socket'

module Barlume

class Lucciola
	def self.wrap (what)
		return what if what.is_a? self

		new(what)
	end

	def initialize (what)
		@io = what.is_a?(::Integer) ? ::IO.for_fd(what) : what

		unless @io.respond_to? :to_i
			raise ArgumentError, 'the object must respond to to_i'
		end

		@fd = @io.to_i
	end

	def respond_to_missing? (*args)
		@io.respond_to? *args
	end

	def method_missing (id, *args, &block)
		if @io.respond_to? id
			return @io.__send__ id, *args, &block
		end

		super
	end

	def == (other)
		to_i == other.to_i
	end

	alias eql? ==

	def equal? (other)
		to_io == (other.respond_to?(:to_io) ? other.to_io : other)
	end

	def hash
		to_i.hash
	end

	def closed?
		@closed or @io.respond_to?(:closed?) ? @io.closed? : false
	end

	def alive?
		if @io.is_a?(Socket)
			!!@io.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE).nonzero?
		else
			!@io.closed?
		end
	end

	def nonblocking?
		!(@io.fcntl(Fcntl::F_GETFL, 0) & Fcntl::O_NONBLOCK).zero?
	end

	alias asynchronous? nonblocking?

	def blocking?
		!nonblocking?
	end

	alias synchronous? blocking?

	def blocking!
		if block_given?
			if was_nonblocking = nonblocking?
				@io.fcntl(Fcntl::F_SETFL, @io.fcntl(Fcntl::F_GETFL, 0) & ~Fcntl::O_NONBLOCK)
			end

			begin
				return yield
			ensure
				nonblocking! if was_nonblocking
			end
		else
			@io.fcntl(Fcntl::F_SETFL, @io.fcntl(Fcntl::F_GETFL, 0) & ~Fcntl::O_NONBLOCK)
		end

		self
	end

	alias sychronous! blocking!

	def nonblocking!
		if block_given?
			if was_blocking = blocking?
				@io.fcntl(Fcntl::F_SETFL, @io.fcntl(Fcntl::F_GETFL, 0) | Fcntl::O_NONBLOCK)
			end

			begin
				return yield
			ensure
				blocking! if was_blocking
			end
		else
			@io.fcntl(Fcntl::F_SETFL, @io.fcntl(Fcntl::F_GETFL, 0) | Fcntl::O_NONBLOCK)
		end

		self
	end

	alias asynchronous! nonblocking!

	def no_delay?
		raise 'no_delay is TCP only' unless @io.is_a? TCPSocket

		@io.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).nonzero?
	end

	def delay?
		!no_delay?
	end

	def no_delay!
		raise 'no_delay is TCP only' unless @io.is_a? TCPSocket

		@io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

		self
	end

	def delay!
		raise 'no_delay is TCP only' unless @io.is_a? TCPSocket

		@io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 0)

		self
	end

	def transaction
		unless to_io.is_a?(TCPSocket) && Socket.const_defined?(:TCP_CORK)
			raise 'transaction is not supported on this kind of IO'
		end

		begin
			@io.setsockopt Socket::IPPROTO_TCP, Socket::TCP_CORK, 1

			yield self
		ensure
			@io.setsockopt Socket::IPPROTO_TCP, Socket::TCP_CORK, 0
		end

		self
	end

	def trap_in (lanterna)
		raise 'already trapped' if @lanterna

		@lanterna = lanterna
	end

	def set_free
		raise 'not trapped' unless @lanterna

		if @lanterna.has?(self)
			@lanterna.remove(self)
		end

		@lanterna = nil
	end

	def readable?
		raise 'not trapped' unless @lanterna

		@lanterna.readable? self
	end

	def readable!
		raise 'not trapped' unless @lanterna

		@lanterna.readable! self

		self
	end

	def no_readable!
		raise 'not trapped' unless @lanterna

		@lanterna.no_readable! self

		self
	end

	def writable?
		raise 'not trapped' unless @lanterna

		@lanterna.writable? self
	end

	def writable!
		raise 'not trapped' unless @lanterna

		@lanterna.writable! self

		self
	end

	def no_writable!
		raise 'not trapped' unless @lanterna

		@lanterna.no_writable! self

		self
	end

	def accept (*args)
		if blocking?
			@io.accept(*args)
		else
			@io.accept_nonblock(*args)
		end
	end

	def accept_nonblock (*args)
		nonblocking! {
			accept(*args)
		}
	end

	def accept_block (*args)
		blocking! {
			accept(*args)
		}
	end

	def read (*args)
		if (result = @io.sysread(*args)).nil?
			@closed = true
		end

		result
	rescue EOFError
		@closed = true

		raise
	end

	def read_nonblock (*args)
		nonblocking! {
			read(*args)
		}
	end

	def read_block (*args)
		blocking! {
			read(*args)
		}
	end

	def write (*args)
		@io.syswrite(*args)
	rescue EOFError
		@closed = true

		raise
	end

	def write_nonblock (*args)
		nonblocking! {
			write(*args)
		}
	end

	def write_block (*args)
		blocking! {
			write(*args)
		}
	end

	def to_io
		@io
	end

	def to_i
		@fd
	end

	def inspect
		"#<#{self.class.name}: #{to_io.inspect}>"
	end
end

end
