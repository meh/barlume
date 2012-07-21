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

module Barlume

class Lanterna
	class << self
		%w[select poll epoll kqueue port].each {|name|
			define_method "#{name}?" do
				const_get(name.capitalize).supported?
			end

			define_method name do
				const_get(name.capitalize).new
			end
		}

		def best
			return kqueue if kqueue?

			return epoll if epoll?
			
			return port if port?

			return poll if poll?

			return select
		end

		def best_edge_triggered
			return kqueue.edge_triggered! if kqueue?

			return epoll.edge_triggered! if epoll?

			raise 'edge triggering is not supported on this platform'
		end

		def new (*)
			raise 'unsupported platform' unless supported?

			super
		end
	end

	Available = Struct.new(:readable, :writable, :error)

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

	include Enumerable

	def initialize
		@breaker       = Breaker.new
		@descriptors   = []
		@report_errors = false
	end

	def name
		self.class.name[/(?:::)?([^:]*)$/, 1].downcase.to_sym
	end

	def each (&block)
		return to_enum unless block

		@descriptors.each(&block)

		self
	end

	def report_errors?
		@report_errors
	end

	def report_errors!
		@report_errors = true

		self
	end

	def dont_report_errors!
		@report_errors = false

		self
	end

	def break
		@breaker.break

		self
	end

	def add (what)
		Lucciola.wrap(what).tap {|l|
			if @descriptors.member?(l)
				raise ArgumentError, "#{what.inspect} is already in the Lanterna"
			end

			@descriptors.push(l)
		}
	end

	def push (*args)
		args.each { |a| add a }

		self
	end

	alias << push

	def remove (what)
		unless result = @descriptors.delete(Lucciola.wrap(what))
			raise ArgumentError, "#{what.inspect} isn't in the Lanterna"
		end

		result
	end

	alias delete remove
end

end

require 'barlume/lanterna/utils'
require 'barlume/lanterna/select'
require 'barlume/lanterna/poll'
require 'barlume/lanterna/epoll'
require 'barlume/lanterna/kqueue'
require 'barlume/lanterna/port'
