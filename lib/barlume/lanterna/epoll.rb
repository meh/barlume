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

class Epoll < Lanterna; begin
	module C
		extend FFI::Library

		ffi_lib FFI::Library::LIBC

		class EpollData < FFI::Union
			layout \
				:ptr, :pointer,
				:fd,  :int,
				:u32, :uint32,
				:u64, :uint64
		end

		class EpollEvent < FFI::Struct
			pack 1

			layout \
				:events, :uint32,
				:data,   EpollData
		end

		Control = FFI::Enum.new([:add, 1, :del, :mod])

		attach_function :epoll_create, [:int], :int
		attach_function :epoll_create1, [:int], :int
		attach_function :epoll_ctl, [:int, Control, :int, :pointer], :int
		attach_function :epoll_wait, [:int, :pointer, :int, :int], :int, :blocking => true

		EPOLLIN  = 0x001
		EPOLLPRI = 0x002
		EPOLLOUT = 0x004

		EPOLLERR  = 0x008
		EPOLLHUP  = 0x010
		EPOLLNVAL = 0x020

		EPOLLRDNORM = 0x040
		EPOLLRDBAND = 0x080
		EPOLLWRNORM = 0x100
		EPOLLWRBAND = 0x200

		EPOLLMSG    = 0x0400
		EPOLLREMOVE = 0x1000
		EPOLLRDHUP  = 0x2000

		EPOLLONESHOT = 1 << 30
		EPOLLET      = 1 << 31
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

		FFI.raise_if((@fd = C.epoll_create1(0)) < 0)

		@ev = C::EpollEvent.new
		@ev[:events]    = C::EPOLLIN
		@ev[:data][:fd] = @breaker.to_i

		FFI.raise_if(C.epoll_ctl(@fd, :add, @breaker.to_i, @ev) < 0)

		self.size = 4096
	end

	def size= (n)
		@events = FFI::MemoryPointer.new C::EpollEvent.size, n
		@size   = @events.size / C::EpollEvent.size
	end

	def edge_triggered?;   @edge; end
	def level_triggered?; !@edge; end

	def edge_triggered!
		@edge = true

		each {|l|
			@ev[:events]    = C::EPOLLET | (l.readable? ? C::EPOLLIN : 0) | (l.writable? ? C::EPOLLOUT : 0)
			@ev[:data][:fd] = l.to_i

			FFI.raise_if(C.epoll_ctl(@fd, :mod, l.to_i, @ev) < 0)
		}
	end

	def level_triggered!
		@edge = false

		each {|l|
			@ev[:events]    = (l.readable? ? C::EPOLLIN : 0) | (l.writable? ? C::EPOLLOUT : 0)
			@ev[:data][:fd] = l.to_i

			FFI.raise_if(C.epoll_ctl(@fd, :mod, l.to_i, @ev) < 0)
		}
	end

	def add (*)
		super {|l|
			@ev[:events]    = 0
			@ev[:data][:fd] = l.to_i

			FFI.raise_if(C.epoll_ctl(@fd, :add, l.to_i, @ev) < 0)
		}
	end

	def remove (*)
		super {|l|
			begin
				FFI.raise_if(C.epoll_ctl(@fd, :del, l.to_i, nil) < 0)
			rescue Errno::ENOENT; end
		}
	end

	def readable! (*)
		super {|l|
			@ev[:events]    = C::EPOLLIN | (l.writable? ? C::EPOLLOUT : 0) | (edge_triggered? ? C::EPOLLET : 0)
			@ev[:data][:fd] = l.to_i

			FFI.raise_if(C.epoll_ctl(@fd, :mod, l.to_i, @ev) < 0)
		}
	end

	def no_readable! (*)
		super {|l|
			@ev[:events]    = (l.writable? ? C::EPOLLOUT : 0) | (edge_triggered? ? C::EPOLLET : 0)
			@ev[:data][:fd] = l.to_i

			FFI.raise_if(C.epoll_ctl(@fd, :mod, l.to_i, @ev) < 0)
		}
	end

	def writable! (*)
		super {|l|
			@ev[:events]    = C::EPOLLOUT | (l.readable? ? C::EPOLLIN : 0) | (edge_triggered? ? C::EPOLLET : 0)
			@ev[:data][:fd] = l.to_i

			FFI.raise_if(C.epoll_ctl(@fd, :mod, l.to_i, @ev) < 0)
		}
	end

	def no_writable! (*)
		super {|l|
			@ev[:events]    = (l.readable? ? C::EPOLLIN : 0) | (edge_triggered? ? C::EPOLLET : 0)
			@ev[:data][:fd] = l.to_i

			FFI.raise_if(C.epoll_ctl(@fd, :mod, l.to_i, @ev) < 0)
		}
	end

	def available (timeout = nil, &block)
		return enum_for :available, timeout unless block

		FFI.raise_if((length = C.epoll_wait(@fd, @events, @size, timeout ? timeout * 1000 : -1)) < 0)

		yield :done

		if length == 0
			yield :timeout, timeout

			return self
		end

		n    = 0
		size = C::EpollEvent.size
		while n < length
			p        = C::EpollEvent.new(@events + (n * size))
			events   = p[:events]
			fd       = p[:data][:fd]
			lucciola = self[fd]

			if lucciola
				if (events & (C::EPOLLERR | C::EPOLLHUP)).nonzero?
					yield :error, lucciola
				else
					if (events & C::EPOLLIN).nonzero?
						yield :readable, lucciola
					end

					if (events & C::EPOLLOUT).nonzero?
						yield :writable, lucciola
					end
				end
			elsif fd == @breaker.to_i
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
