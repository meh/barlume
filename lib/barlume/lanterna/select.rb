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

class Select < Lanterna
	def self.supported?
		true
	end

	def available (timeout = nil)
		readable, writable, error = IO.select([@breaker.to_io] + @readable.values, @writable.values, @readable.values + @writable.values, timeout)

		if readable && readable.delete(@breaker.to_io)
			@breaker.flush
		end

		Available.new(readable, writable, error, readable.nil?)
	end
end

end; end
