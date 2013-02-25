Kernel.load 'lib/barlume/version.rb'

Gem::Specification.new {|s|
	s.name         = 'barlume'
	s.version      = Barlume.version
	s.author       = 'meh.'
	s.email        = 'meh@paranoici.org'
	s.homepage     = 'http://github.com/meh/barlume'
	s.platform     = Gem::Platform::RUBY
	s.summary      = 'A dim light over asynchronous I/O land.'

	s.files         = `git ls-files`.split("\n")
	s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
	s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
	s.require_paths = ['lib']

	s.add_runtime_dependency 'ffi'
}
