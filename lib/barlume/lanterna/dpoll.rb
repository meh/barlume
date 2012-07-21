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

class DPoll < Lanterna; begin
	raise unless File.exists?('/dev/poll')

	module C
		extend FFI::Library

		ffi_lib FFI::Library::LIBC

		class PollFD < FFI::Struct
			layout \
				:fd,      :int,
				:events,  :short,
				:revents, :short
		end

		class DVPoll < FFI::Struct
			layout \
				:fds,     :pointer,
				:nfds,    :nfds_t,
				:timeout, :int
		end

		attach_function :malloc, [:size_t], :pointer
		attach_function :realloc, [:pointer, :size_t], :pointer
		attach_function :free, [:pointer], :void

		DP_POLL = (0xD0 << 8) | 1

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

		@descriptors_by_fd = {}

		@out        = C::DVPoll.new
		@out[:fds]  = FFI::AutoPointer.new(C.malloc(C::PollFD.size), C.method(:free))
		@out[:nfds] = 1

		@set = FFI::AutoPointer.new(C.malloc(C::PollFD.size), C.method(:free))

		pfd          = C::PollFD.new(@set + 0)
		pfd[:fd]     = @breaker.to_i
		pfd[:events] = C::POLLIN
	end

	def add (what)
		super.tap {|l|
			@set.autorelease = false
			@set = FFI::AutoPointer.new(C.realloc(@set, (@descriptors.length + 1) * C::PollFD.size), C.method(:free))

			@out[:fds].autorelease = false
			@out[:fds]   = FFI::AutoPointer.new(C.realloc(@out[:fds], (@descriptors.length + 1) * C::PollFD.size), C.method(:free))
			@out[:nfds] += 1

			pfd = C::PollFD.new(@set + @descriptors.length * C::PollFD.size)
			pfd[:fd] = l.to_i

			@descriptors_by_fd[l.to_i] = l

			@last = nil
		}
	end

	def remove (what)
		Lucciola.wrap(what).tap {|l|
			index   = @descriptors.index(l)
			offset  = (index + 1) * C::PollFD.size
			pointer = @set + offset

			pointer.write_bytes((pointer + C::PollFD.size).read_bytes((@descriptors.length - index) * C::PollFD.size))

			@set.autorelease = false
			@set = FFI::AutoPointer.new(C.realloc(@set, (@descriptors.length) * C::PollFD.size), C.method(:free))

			@out[:fds].autorelease = false
			@out[:fds]   = FFI::AutoPointer.new(C.realloc(@out[:fds], (@descriptors.length) * C::PollFD.size), C.method(:free))
			@out[:nfds] -= 1

			@descriptors_by_fd.delete(l.to_i)

			super(l)
		}
	end

	def available (timeout = nil)
		set :both; dpoll timeout

		Available.new(to(:read), to(:write), to(:error))
	end

	def readable (timeout = nil)
		set :read; dpoll timeout

		report_errors? ? [to(:read), to(:error)] : to(:read)
	end

	def writable (timeout = nil)
		set :write; dpoll timeout

		report_errors? ? [to(:write), to(:error)] : to(:write)
	end

	def set (what)
		return if @last == what

		events = case what
			when :both  then C::POLLIN | C::POLLOUT
			when :read  then C::POLLIN
			when :write then C::POLLOUT
		end

		1.upto(@descriptors.length) {|n|
			pfd = C::PollFD.new(@set + (n * C::PollFD.size))
			pfd[:events] = events
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

		0.upto(@length - 1) {|n|
			pfd = C::PollFD.new(@out[:fds] + (n * C::PollFD.size))

			next if pfd[:fd] == @breaker.to_i

			if (pfd[:revents] & events).nonzero?
				result << @descriptors_by_fd[pfd[:fd]]
			end
		}

		result
	end

	def dpoll (timeout = nil)
		@out[:timeout] = timeout ? timeout * 1000 : -1

		io = IO.for_fd(IO.sysopen('/dev/poll', IO::RDWR))
		io.syswrite(@set.read_bytes((@descriptors.length + 1) * C::PollFD.size))

		@length = io.ioctl(C::DP_POLL, @out.pointer.address)

		@breaker.flush
	end
rescue Exception
	def self.supported?
		false
	end
end; end

end; end
