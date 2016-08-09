lib = File.join File.dirname(__FILE__), 'lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'fluffle/version'

Gem::Specification.new do |s|
  s.name     = 'fluffle'
  s.version  = Fluffle::VERSION
  s.authors  = ['Dirk Gadsden']
  s.email    = ['dirk@esherido.com']
  s.summary  = ''
  s.homepage = 'https://github.com/Everlane/fluffle'
  s.license  = 'MIT'

  s.required_ruby_version = '>= 1.9.3'

  s.add_dependency 'bunny',           '~> 2.5.0'
  s.add_dependency 'concurrent-ruby', '~> 1.0.2'
  s.add_dependency 'oj',              '~> 2.17.1'
  s.add_dependency 'uuidtools',       '~> 2.1.5'

  s.add_development_dependency 'rspec', '~> 3.4.0'
  s.add_development_dependency 'pry',   '~> 0.10.1'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- test/*`.split("\n")
end
