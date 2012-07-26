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

require 'barlume/lucciola'

require 'barlume/lanterna/helpers'
require 'barlume/lanterna/select'
require 'barlume/lanterna/poll'
require 'barlume/lanterna/epoll'
require 'barlume/lanterna/kqueue'
require 'barlume/lanterna/port'
require 'barlume/lanterna/dpoll'

module Barlume

class Lanterna
	%w[select poll epoll kqueue port dpoll].each {|name|
		klass = Lanterna.const_get(Lanterna.constants.find { |c| c.downcase.to_s == name })

		define_singleton_method "#{name}?" do
			klass.supported?
		end

		define_singleton_method name do
			klass.new
		end
	}

	def self.best
		return kqueue if kqueue?

		return epoll if epoll?
		
		return port if port?

		return dpoll if dpoll? && RUBY_PLATFORM =~ /solaris/i

		return poll if poll?

		return select
	end

	def self.best_edge_triggered
		return kqueue.edge_triggered! if kqueue?

		return epoll.edge_triggered! if epoll?

		raise 'edge triggering is not supported on this platform'
	end

	def self.new (*)
		raise 'unsupported platform' unless supported?

		super
	end

	include Enumerable

	def initialize
		@breaker     = Breaker.new
		@descriptors = {}
		@readable    = {}
		@writable    = {}
	end

	def name
		self.class.name[/(?:::)?([^:]*)$/, 1].downcase.to_sym
	end

	def break
		@breaker.break

		self
	end

	def add (what, mode = nil, &block)
		Lucciola.wrap(what).tap {|l|
			if @descriptors.has_key?(l.to_i)
				raise ArgumentError, "#{what.inspect} is already trapped"
			end

			@descriptors[l.to_i] = l
			l.trap_in self
			block.call l if block

			readable! what if mode == :readable || mode == :both
			writable! what if mode == :writable || mode == :both
		}
	end

	def push (*args)
		args.each { |a| add a }

		self
	end

	alias << push

	def remove (what, &block)
		unless what = @descriptors[what.to_i]
			raise ArgumentError, "#{what.inspect} isn't trapped here"
		end

		block.call what if block
		@descriptors.delete(what.to_i)
		what.set_free
	end

	alias delete remove

	def has? (what)
		@descriptors.has_key?(what.to_i)
	end

	def [] (what)
		@descriptors[what.to_i]
	end

	def each (mode = nil, &block)
		return enum_for :each, mode unless block

		if mode.nil?
			@descriptors.each_value(&block)
		elsif mode == :readable
			@readable.each_value(&block)
		elsif mode == :writeable
			@writable.each_value(&block)
		else
			raise ArgumentError, "#{mode} is an unknown mode"
		end

		self
	end

	def readable (&block)
		each(:readable, &block)
	end

	def readable! (*args, &block)
		args.flatten!
		args.compact!

		if args.empty?
			each { |c| readable! c, &block }
		else
			args.each {|what|
				unless readable?(what)
					what = self[what]

					block.call what if block
					@readable[what.to_i] = what
				end
			}
		end

		self
	end

	def no_readable! (*args, &block)
		args.flatten!
		args.compact!

		if args.empty?
			each { |c| readable! c, &block }
		else
			args.each {|what|
				if what = readable?(what)
					@readable.delete(what.to_i)
					block.call what if block
				end
			}
		end

		self
	end

	def readable? (what = nil)
		return !@readable.empty? unless what

		return false unless what = @readable[what.to_i]

		what
	end

	def writable (&block)
		each(:writable, &block)
	end

	def writable! (*args, &block)
		args.flatten!
		args.compact!

		if args.empty?
			each { |c| writable! c, &block }
		else
			args.each {|what|
				unless writable?(what)
					what = self[what]

					block.call what if block
					@writable[what.to_i] = what
				end
			}
		end

		self
	end

	def no_writable! (*args, &block)
		args.flatten!
		args.compact!

		if args.empty?
			each { |c| writable! c, &block }
		else
			args.each {|what|
				if what = writable?(what)
					@writable.delete(what.to_i)
					block.call what if block
				end
			}
		end

		self
	end

	def writable? (what = nil)
		return !@writable.empty? unless what

		return false unless what = @writable[what.to_i]

		what
	end

	class Available
		attr_reader :readable, :writable, :error

		def initialize (readable = nil, writable = nil, error = nil, timeout = false)
			@readable = readable || []
			@writable = writable || []
			@error    = error    || []

			@timeout = timeout
		end

		def timeout?
			@timeout
		end

		def to_a
			[@readable, @writable, @error, @timeout]
		end
	end

	class Breaker
		def initialize
			@pipes = IO.pipe
		end

		def break
			@pipes.last.write_nonblock 'x'
		end

		def flush
			@pipes.first.read_nonblock 2048 rescue nil
		end

		def to_io
			@pipes.first
		end

		def to_i
			to_io.to_i
		end
	end
end

end
