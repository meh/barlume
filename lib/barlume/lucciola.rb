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
	end

	def respond_to_missing? (*args)
		@io.respond_to? *args
	end

	def method_missing (id, *args, &block)
		if @io.respond_to? id
			begin
				return @io.__send__ id, *args, &block
			rescue EOFError
				@closed = true

				raise
			end
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

	def nonblocking?
		(@io.fcntl(Fcntl::F_GETFL, 0) & Fcntl::O_NONBLOCK).nonzero?
	end

	alias asynchronous? nonblocking?

	def blocking?
		!nonblocking?
	end

	def blocking!
		@io.fcntl(Fcntl::F_SETFL, @io.fcntl(Fcntl::F_GETFL, 0) | Fcntl::O_NONBLOCK)
	end

	def nonblocking!
		@io.fcntl(Fcntl::F_SETFL, @io.fcntl(Fcntl::F_GETFL, 0) & ~Fcntl::O_NONBLOCK)
	end

	def to_io
		@io
	end

	def to_i
		@io.to_i
	end

	def inspect
		"#<#{self.class.name}: #{to_io.inspect}>"
	end
end

end
