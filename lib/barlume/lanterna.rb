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

		raise 'this platform does not support edge triggered primitives'
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

	def break (with = nil)
		@breaker.break(with)

		self
	end

	def add (what, mode = nil, &block)
		Lucciola.wrap(what).tap {|lucciola|
			if @descriptors.has_key?(lucciola.to_i)
				raise ArgumentError, "#{what.inspect} is already trapped"
			end

			@descriptors[lucciola.to_i] = lucciola
			lucciola.trap_in self
			block.call lucciola if block

			readable! lucciola if mode == :readable || mode == :both
			writable! lucciola if mode == :writable || mode == :both
		}
	end

	def push (*args)
		args.each { |a| add a }

		self
	end

	alias << push

	def remove (what, &block)
		unless lucciola = @descriptors[what.to_i]
			raise ArgumentError, "#{what.inspect} isn't trapped here"
		end

		block.call lucciola if block

		@descriptors.delete(lucciola.to_i)
		@readable.delete(lucciola.to_i)
		@writable.delete(lucciola.to_i)

		lucciola.set_free
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
		elsif mode == :writable
			@writable.each_value(&block)
		else
			raise ArgumentError, "#{mode} is an unknown mode"
		end

		self
	end

	def each_readable (&block)
		each(:readable, &block)
	end

	def each_writable (&block)
		each(:writable, &block)
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
			each(:readable) { |c| readable! c, &block }
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
			each(:writable) { |c| writable! c, &block }
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

	def available (timeout = nil, &block)
		raise NotImplementedError, 'available has not been implemented'
	end

	def readable (timeout = nil, &block)
		readable = @readable.dup
		writable = @writable.dup

		no_writable!
		readable!

		result = available(timeout, &block)

		no_readable! @readable - readable
		writable! writable

		result
	end

	def writable (timeout = nil, &block)
		readable = @readable.dup
		writable = @writable.dup

		no_readable!
		writable!

		result = available(timeout, &block)

		no_writable! @writable - writable
		readable! readable

		result
	end

	class Breaker
		def initialize
			@pipes = IO.pipe
		end

		def break (with = nil)
			@pipes.last.write(Marshal.dump(with))
		end

		def reason
			Marshal.load(@pipes.first)
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
