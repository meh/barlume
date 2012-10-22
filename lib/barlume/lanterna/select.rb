#--
# Copyleft (ɔ) meh. - http://meh.schizofreni.co
#
# This file is part of barlume - https://github.com/meh/barlume
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

class Select < Lanterna
	def self.supported?
		true
	end

	def available (timeout = nil, &block)
		return enum_for :available, timeout unless block

		readable, writable, error = IO.select([@breaker.to_io] + @readable.values, @writable.values, @descriptors.values, timeout)

		yield :done

		unless readable
			yield :timeout, timeout

			return self
		end

		error.each {|io|
			readable.delete(io)
			writable.delete(io)

			yield :error, io
		}

		readable.each {|io|
			if io == @breaker.to_io
				yield :break, @breaker.reason
			else
				yield :readable, io
			end
		}

		writable.each {|io|
			yield :writable, io
		}

		self
	end
end

end; end
