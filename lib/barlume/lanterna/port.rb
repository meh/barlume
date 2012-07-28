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

class Port < Lanterna; begin
	module C
		extend FFI::Library

		ffi_lib FFI::Library::LIBC

		class PortEvent < FFI::Struct
			layout \
				:events, :int,
				:source, :ushort,
				:pad,    :ushort,
				:object, :uintptr_t,
				:user,   :pointer
		end

		class TimeSpec < FFI::Struct
			layout \
				:tv_sec,  :time_t,
				:tv_nsec, :int
		end

		attach_function :port_create, [], :int
		attach_function :port_associate, [:int, :int, :uintptr_t, :int, :pointer], :int
		attach_function :port_dissociate, [:int, :int, :uintptr_t], :int
		attach_function :port_send, [:int, :int, :pointer], :int
		attach_function :port_sendn, [:pointer, :pointer, :uint, :int, :pointer], :int
		attach_function :port_get, [:int, :pointer, :pointer], :int
		attach_function :port_getn, [:int, :pointer, :uint, :pointer, :pointer], :int
		attach_function :port_alert, [:int, :int, :int, :pointer], :int

		SOURCE_AIO   = 1
		SOURCE_TIMER = 2
		SOURCE_USER  = 3
		SOURCE_FD    = 4
		SOURCE_ALERT = 5
		SOURCE_MQ    = 6
		SOURCE_FILE  = 7

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

	def self.new (*)
		super.tap {|c|
			ObjectSpace.define_finalizer c, finalizer(c.instance_variable_get :@fd)
		}
	end

	def self.finalizer (fd)
		proc {
			IO.for_fd(fd).close
		}
	end

	attr_reader :size

	def initialize
		super

		FFI.raise_if((@fd = C.port_create) < 0)
		FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, @breaker.to_i, C::POLLIN, nil) < 0)

		@timeout = C::TimeSpec.new
		@length  = FFI::MemoryPointer.new :uint

		self.size = 4096
	end

	def size= (n)
		@events = FFI::MemoryPointer.new C::PortEvent.size, n
		@size   = @events.size / C::PortEvent.size
	end

	def add (*)
		super {|l|
			FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, l.to_i, C::POLLIN, nil) < 0)
		}
	end

	def remove (*)
		super {|l|
			begin
				FFI.raise_if(C.port_dissociate(@fd, C::SOURCE_FD, l.to_i) < 0)
			rescue Errno::EIDRM; end
		}
	end

	def readable! (*)
		super {|l|
			FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, l.to_i, C::POLLIN | (l.writable? ? C::POLLOUT : 0), nil) < 0)
		}
	end

	def no_readable! (*)
		super {|l|
			FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, l.to_i, (l.writable? ? C::POLLOUT : 0), nil) < 0)
		}
	end

	def writable! (*)
		super {|l|
			FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, l.to_i, C::POLLOUT | (l.readable? ? C::POLLIN : 0), nil) < 0)
		}
	end

	def no_writable! (*)
		super {|l|
			FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, l.to_i, (l.readable? ? C::POLLIN : 0), nil) < 0)
		}
	end

	def available (timeout = nil, &block)
		return enum_for :available, timeout unless block

		if timeout
			@timeout[:tv_sec]  = timeout.to_i
			@timeout[:tv_nsec] = (timeout - timeout.to_i) * 1000
		end

		@length.write_uint 1

		if C.port_getn(@fd, @events, size, @length, timeout ? @timeout : nil) < 0
			FFI.raise_unless FFI.errno == Errno::ETIME::Errno

			yield :timeout, timeout

			return self
		end

		n      = 0
		size   = C::PortEvent.size
		length = @length.read_uint
		while n < length
			p        = C::PortEvent.new(@events + (n * size))
			events   = p[:events]
			fd       = p[:object]
			lucciola = self[fd]

			if lucciola
				FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, lucciola.to_i, (lucciola.readable? ? C::POLLIN : 0) | (lucciola.writable? ? C::POLLOUT : 0), nil) < 0)

				if (events & (C::POLLERR | C::POLLHUP)).nonzero?
					yield :error, lucciola
				else
					if (events & C::POLLIN).nonzero?
						yield :readable, lucciola
					end

					if (events & C::POLLOUT).nonzero?
						yield :writable, lucciola
					end
				end
			elsif fd == @breaker.to_i
				FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, @breaker.to_i, C::POLLIN, nil) < 0)

				yield :break, @breaker.reason
			else
				raise "#{fd} isn't trapped here"
			end

			n += 1
		end

		self
	end
rescue Exception
	def self.supported?
		false
	end
end; end

end; end
