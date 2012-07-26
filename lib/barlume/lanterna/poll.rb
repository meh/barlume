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

	def available (timeout = nil)
		poll timeout

		Available.new(to(:read), to(:write), to(:error), timeout?)
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

	def to (what)
		result = []

		return result if timeout?

		events = case what
			when :read  then C::POLLIN
			when :write then C::POLLOUT
			when :error then C::POLLERR | C::POLLHUP
		end

		1.upto(@descriptors.length) {|n|
			pfd = C::PollFD.new(@set + (n * C::PollFD.size))

			next if pfd[:fd] == @breaker.to_i

			if (pfd[:revents] & events).nonzero?
				result << self[pfd[:fd]]
			end
		}

		result
	end

	def index_of (what)
		@descriptors.keys.index(what.to_i)
	end

	private :index_of

	def timeout?
		@length == 0
	end

	private :timeout?

	def poll (timeout = nil)
		FFI.raise_if((@length = C.poll(@set, @descriptors.length + 1, timeout ? timeout * 1000 : -1)) < 0)

		@breaker.flush
	end

rescue Exception
	def self.supported?
		false
	end
end; end

end; end
