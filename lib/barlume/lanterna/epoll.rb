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

		MAX = 4294967295

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

	def initialize
		super

		FFI.raise_if((@fd = C.epoll_create1(0)) < 0)

		p = C::EpollEvent.new
		p[:events] = C::EPOLLIN
		p[:data][:u32] = C::MAX

		FFI.raise_if(C.epoll_ctl(@fd, :add, @breaker.to_i, p) < 0)

		self.size = 4096
	end

	def size
		@events.size / C::EpollEvent.size
	end

	def size= (n)
		@events = FFI::MemoryPointer.new C::EpollEvent.size, n
	end

	def edge_triggered?;   @edge; end
	def level_triggered?; !@edge; end

	def edge_triggered!
		@edge = true
		@last = nil

		self
	end

	def level_triggered!
		@edge = false
		@last = nil

		self
	end

	def add (what)
		super.tap {|l|
			FFI.raise_if(C.epoll_ctl(@fd, :add, l.to_i, C::EpollEvent.new) < 0)

			@last = nil
		}
	end

	def remove (what)
		super.tap {|l|
			begin
				FFI.raise_if(C.epoll_ctl(@fd, :del, l.to_i, nil) < 0)
			rescue Errno::ENOENT; end

			@last = nil
		}
	end

	def available (timeout = nil)
		set :both; epoll timeout

		Available.new(to(:read), to(:write), to(:error))
	end

	def readable (timeout = nil)
		set :read; epoll timeout

		report_errors? ? [to(:read), to(:error)] : to(:read)
	end

	def writable (timeout = nil)
		set :write; epoll timeout

		report_errors? ? [to(:write), to(:error)] : to(:write)
	end

	def set (what)
		return if @last == what

		p = C::EpollEvent.new
		p[:events] = case what
			when :both  then C::EPOLLIN | C::EPOLLOUT
			when :read  then C::EPOLLIN
			when :write then C::EPOLLOUT
		end

		p[:events] |= C::EPOLLET if edge_triggered?

		each_with_index {|descriptor, index|
			p[:data][:u32] = index

			FFI.raise_if(C.epoll_ctl(@fd, :mod, descriptor.to_i, p) < 0)
		}

		@last = what
	end

	def to (what)
		result = []
		events = case what
			when :read  then C::EPOLLIN
			when :write then C::EPOLLOUT
			when :error then C::EPOLLERR | C::EPOLLHUP
		end

		0.upto(@length - 1) {|n|
			p = C::EpollEvent.new(@events + (n * C::EpollEvent.size))

			if p[:data][:u32] != C::MAX && (p[:events] & events).nonzero?
				result << @descriptors[p[:data][:u32]]
			end
		}

		result
	end

	def epoll (timeout = nil)
		FFI.raise_if((@length = C.epoll_wait(@fd, @events, size, timeout ? timeout * 1000 : -1)) < 0)

		@breaker.flush
	end
rescue Exception
	def self.supported?
		false
	end
end; end

end; end
