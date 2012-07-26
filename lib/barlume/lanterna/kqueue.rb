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

class Kqueue < Lanterna; begin
	module C
		extend FFI::Library

		ffi_lib FFI::Library::LIBC

		class Kevent < FFI::Struct
			layout \
				:ident,  :intptr_t,
				:filter, :short,
				:flags,  :ushort,
				:fflags, :uint,
				:data,   :long,
				:udata,  :pointer
		end

		class TimeSpec < FFI::Struct
			layout \
				:tv_sec,  :time_t,
				:tv_nsec, :int
		end

		attach_function :kqueue, [], :int
		attach_function :kevent, [:int, :pointer, :int, :pointer, :int, :pointer], :int, :blocking => true

		EVFILT_READ     =  -1
		EVFILT_WRITE    =  -2
		EVFILT_AIO      =  -3
		EVFILT_VNODE    =  -4
		EVFILT_PROC     =  -5
		EVFILT_SIGNAL   =  -6
		EVFILT_TIMER    =  -7
		EVFILT_NETDEV   =  -8
		EVFILT_FS       =  -9
		EVFILT_LIO      = -10
		EVFILT_USER     = -11
		EVFILT_SYSCOUNT =  11

		EV_ADD      = 0x0001
		EV_DELETE   = 0x0002
		EV_ENABLE   = 0x0004
		EV_DISABLE  = 0x0008
		EV_ONESHOT  = 0x0010
		EV_CLEAR    = 0x0020
		EV_RECEIPT  = 0x0040
		EV_DISPATCH = 0x0080
		EV_SYSFLAGS = 0xF000
		EV_FLAG1    = 0x2000
		EV_EOF      = 0x8000
		EV_ERROR    = 0x4000

		def self.EV_SET (event, a, b, c, d, e, f)
			event[:ident]  = a
			event[:filter] = b
			event[:flags]  = c
			event[:fflags] = d
			event[:data]   = e
			event[:udata]  = f

			event
		end
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

	def initialize
		super

		FFI.raise_if((@fd = C.kqueue) < 0)

		@timeout = C::TimeSpec.new
		@ev      = C::Kevent.new

		FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, @breaker.to_i, C::EVFILT_READ, C::EV_ADD | C::EV_ENABLE, 0, 0, 0), 1, nil, 0, nil) < 0)

		self.size = 4096
	end

	def size
		@events.size / C::Kevent.size
	end

	def size= (n)
		@events = FFI::MemoryPointer.new C::Kevent.size, n
	end

	def edge_triggered?;   @edge; end
	def level_triggered?; !@edge; end

	def edge_triggered!
		@edge = true

		each {|l|
			if l.readable?
				FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_READ, C::EV_ADD | C::EV_ENABLE | C::EV_CLEAR, 0, 0, l.to_i), 1, nil, 0, nil) < 0)
			end

			if l.writable?
				FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_WRITE, C::EV_ADD | C::EV_ENABLE | C::EV_CLEAR, 0, 0, l.to_i), 1, nil, 0, nil) < 0)
			end
		}
	end

	def level_triggered!
		@edge = false

		each {|l|
			if l.readable?
				FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_READ, C::EV_ADD | C::EV_ENABLE, 0, 0, l.to_i), 1, nil, 0, nil) < 0)
			end

			if l.writable?
				FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_WRITE, C::EV_ADD | C::EV_ENABLE, 0, 0, l.to_i), 1, nil, 0, nil) < 0)
			end
		}
	end

	def remove (*)
		super {|l|
			begin
				FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_READ, C::EV_DELETE | C::EV_DISABLE, 0, 0, 0), 1, nil, 0, nil) < 0)
			rescue Errno::ENOENT; end

			begin
				FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_WRITE, C::EV_DELETE | C::EV_DISABLE, 0, 0, 0), 1, nil, 0, nil) < 0)
			rescue Errno::ENOENT; end
		}
	end

	def available (timeout = nil)
		kevent timeout

		Available.new(to(:read), to(:write), to(:error), timeout?)
	end

	def readable! (*)
		super {|l|
			FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_READ, C::EV_ADD | C::EV_ENABLE | (edge_triggered? ? C::EV_CLEAR : 0), 0, 0, 0), 1, nil, 0, nil) < 0)
		}
	end

	def no_readable! (*)
		super {|l|
			FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_READ, C::EV_ADD | C::EV_DISABLE, 0, 0, 0), 1, nil, 0, nil) < 0)
		}
	end

	def writable! (*)
		super {|l|
			FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_WRITE, C::EV_ADD | C::EV_ENABLE | (edge_triggered? ? C::EV_CLEAR : 0), 0, 0, 0), 1, nil, 0, nil) < 0)
		}
	end

	def no_writable! (*)
		super {|l|
			FFI.raise_if(C.kevent(@fd, C::EV_SET(@ev, l.to_i, C::EVFILT_WRITE, C::EV_ADD | C::EV_DISABLE, 0, 0, 0), 1, nil, 0, nil) < 0)
		}
	end

	def to (what)
		result = []

		return result if timeout?

		if what == :error
			0.upto(@length - 1) {|n|
				p = C::Kevent.new(@events + (n * C::Kevent.size))

				if (p[:flags] & C::EV_ERROR).nonzero? && lucciola = self[p[:ident]]
					result << lucciola
				end
			}
		else
			filter = case what
				when :read  then C::EVFILT_READ
				when :write then C::EVFILT_WRITE
			end

			0.upto(@length - 1) {|n|
				p = C::Kevent.new(@events + (n * C::Kevent.size))

				if p[:filter] == filter && lucciola = self[p[:ident]]
					result << lucciola
				end
			}
		end

		result
	end

	def timeout?
		@length == 0
	end

	private :timeout?

	def kevent (timeout = nil)
		if timeout
			@timeout[:tv_sec]  = timeout.to_i
			@timeout[:tv_nsec] = (timeout - timeout.to_i) * 1000
		end

		FFI.raise_if((@length = C.kevent(@fd, nil, 0, @events, size, timeout ? @timeout : nil)) < 0)

		@breaker.flush
	end
rescue Exception
	def self.supported?
		false
	end
end; end

end; end
