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

require 'ffi'

module FFI
	def self.errno_exception
		Errno.const_get(Errno.constants[FFI.errno]).new
	end

	def self.raise
		Kernel.raise errno_exception
	rescue Exception => e
		e.backtrace.shift(3)

		Kernel.raise e
	end

	def self.raise_unless (what)
		what ? what : FFI.raise
	rescue Exception => e
		e.backtrace.shift(1)

		Kernel.raise e
	end

	def self.raise_if (what)
		what ? FFI.raise : what
	rescue Exception => e
		e.backtrace.shift(1)

		Kernel.raise e
	end
end
