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

		MAX = 4294967295

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

	def initialize
		super

		FFI.raise_if((@fd = C.port_create) < 0)
		FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, @breaker.to_i, C::POLLIN, FFI::Pointer.new(C::MAX)) < 0)

		@timeout = C::TimeSpec.new
		@length  = FFI::MemoryPointer.new :uint

		self.size = 4096
	end

	def size
		@events.size / C::PortEvent.size
	end

	def size= (n)
		@events = FFI::MemoryPointer.new C::PortEvent.size, n
	end

	def add (*)
		super.tap {
			@last = nil
		}
	end

	def remove (*)
		super.tap {|l|
			begin
				FFI.raise_if(C.port_dissociate(@fd, C::SOURCE_FD, l.to_i) < 0)
			rescue Errno::EIDRM; end

			@last = nil
		}
	end

	def available (timeout = nil)
		set :both; port timeout

		Available.new(to(:read), to(:write), to(:error))
	end

	def readable (timeout = nil)
		set :read; port timeout

		report_errors? ? [to(:read), to(:error)] : to(:read)
	end

	def writable (timeout = nil)
		set :write; port timeout

		report_errors? ? [to(:write), to(:error)] : to(:write)
	end

	def set (what)
		return if @last == what

		events = case what
			when :both  then C::POLLIN | C::POLLOUT
			when :read  then C::POLLIN
			when :write then C::POLLOUT
		end

		each_with_index {|descriptor, index|
			FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, descriptor.to_i, events, FFI::Pointer.new(index)) < 0)
		}

		@last = what
	end

	def to (what)
		result = []
		events = case what
			when :read  then C::POLLIN
			when :write then C::POLLOUT
			when :error then C::POLLERR | C::POLLHUP
		end

		0.upto(@length.read_uint - 1) {|n|
			p     = C::PortEvent.new(@events + (n * C::PortEvent.size))
			index = p[:user].address

			next unless p[:source] == C::SOURCE_FD

			if index != C::MAX && (p[:events] & events).nonzero?
				result << @descriptors[index]
			end
		}

		result
	end

	def reassociate!
		events = case @last
			when :both  then C::POLLIN | C::POLLOUT
			when :read  then C::POLLIN
			when :write then C::POLLOUT
		end

		0.upto(@length.read_uint - 1) {|n|
			p     = C::PortEvent.new(@events + (n * C::PortEvent.size))
			index = p[:user].address

			next unless p[:source] == C::SOURCE_FD

			if index == C::MAX
				FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, @breaker.to_i, C::POLLIN, FFI::Pointer.new(C::MAX)) < 0)
			else
				FFI.raise_if(C.port_associate(@fd, C::SOURCE_FD, p[:object], events, p[:user]) < 0)
			end
		}
	end

	def port (timeout = nil)
		if timeout
			@timeout[:tv_sec]  = timeout.to_i
			@timeout[:tv_nsec] = (timeout - timeout.to_i) * 1000
		end

		@length.write_uint 1

		if C.port_getn(@fd, @events, size, @length, timeout ? @timeout : nil) < 0
			FFI.raise_unless FFI.errno == Errno::ETIME::Errno
		end

		reassociate!

		@breaker.flush
	end
rescue Exception
	def self.supported?
		false
	end
end; end

end; end
