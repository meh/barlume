#--
# Copyleft (ɔ) meh. - http://meh.schizofreni.co
#
# This file is part of barlume - https://github.com/meh/barlume
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

module Barlume; class Lanterna

class Poll < Lanterna; begin
	module C
		extend FFI::Library

		ffi_lib FFI::Library::LIBC

		class PollFD < FFI::Struct
			layout \
				:fd,      :int,
				:events,  :short,
				:revents, :short
		end

		attach_function :poll, [:pointer, :ulong, :int], :int, :blocking => true

		attach_function :malloc, [:size_t], :pointer
		attach_function :realloc, [:pointer, :size_t], :pointer
		attach_function :free, [:pointer], :void

		POLLIN  = 0x001
		POLLPRI = 0x002
		POLLOUT = 0x004

		POLLERR  = 0x008
		POLLHUP  = 0x010
		POLLNVAL = 0x020

		POLLRDNORM = 0x040
		POLLRDBAND = 0x080
		POLLWRNORM = 0x100
		POLLWRBAND = 0x200

		POLLMSG    = 0x0400
		POLLREMOVE = 0x1000
		POLLRDHUP  = 0x2000
	end

	def self.supported?
		true
	end

	def initialize
		super

		@set = FFI::AutoPointer.new(C.malloc(C::PollFD.size), C.method(:free))

		pfd          = C::PollFD.new(@set + 0)
		pfd[:fd]     = @breaker.to_i
		pfd[:events] = C::POLLIN
	end

	def add (*)
		super {|l|
			@set.autorelease = false
			@set = FFI::AutoPointer.new(C.realloc(@set, (@descriptors.length + 1) * C::PollFD.size), C.method(:free))

			pfd = C::PollFD.new(@set + (@descriptors.length * C::PollFD.size))
			pfd[:fd] = l.to_i
		}
	end

	def remove (*)
		super {|l|
			index   = index_of(l)
			offset  = (index + 1) * C::PollFD.size
			pointer = @set + offset

			pointer.write_bytes((pointer + C::PollFD.size).read_bytes((@descriptors.length - index) * C::PollFD.size))

			@set.autorelease = false
			@set = FFI::AutoPointer.new(C.realloc(@set, @descriptors.length * C::PollFD.size), C.method(:free))
		}
	end

	def readable! (*)
		super {|l|
			pfd = C::PollFD.new(@set + ((index_of(l) + 1) * C::PollFD.size))
			pfd[:events] |= C::POLLIN
		}
	end

	def no_readable! (*)
		super {|l|
			pfd = C::PollFD.new(@set + ((index_of(l) + 1) * C::PollFD.size))
			pfd[:events] &= ~C::POLLIN
		}
	end

	def writable! (*)
		super {|l|
			pfd = C::PollFD.new(@set + ((index_of(l) + 1) * C::PollFD.size))
			pfd[:events] |= C::POLLOUT
		}
	end

	def no_writable! (*)
		super {|l|
			pfd = C::PollFD.new(@set + ((index_of(l) + 1) * C::PollFD.size))
			pfd[:events] &= ~C::POLLOUT
		}
	end

	def available (timeout = nil, &block)
		return enum_for :available, timeout unless block

		FFI.raise_if((length = C.poll(@set, @descriptors.length + 1, timeout ? timeout * 1000 : -1)) < 0)

		yield :done

		if length == 0
			yield :timeout, timeout

			return self
		end

		if (C::PollFD.new(@set)[:revents] & C::POLLIN).nonzero?
			yield :break, @breaker.reason
		end

		n      = 0
		size   = C::PollFD.size
		result = []
		while n < @descriptors.length
			p        = C::PollFD.new(@set + ((n + 1) * size))
			events   = p[:revents]
			fd       = p[:fd]
			lucciola = self[fd]

			if (events & (C::POLLERR | C::POLLHUP)).nonzero?
				result << [:error, lucciola]
			else
				if (events & C::POLLIN).nonzero?
					result << [:readable, lucciola]
				end

				if (events & C::POLLOUT).nonzero?
					result << [:writable, lucciola]
				end
			end

			n += 1
		end

		result.each(&block)

		self
	end

private
	def index_of (what)
		@descriptors.keys.index(what.to_i)
	end
rescue Exception
	def self.supported?
		false
	end
end; end

end; end
