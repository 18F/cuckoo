# frozen_string_literal: true
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cuckoo/version'

Gem::Specification.new do |spec|
  spec.name          = 'cuckoo'
  spec.version       = Cuckoo::VERSION
  spec.authors       = ['Andy Brody']
  spec.email         = ['git@abrody.com']
  spec.summary       = 'Simple, distributed cron using Redis locks (placeholder)'
  spec.description   = <<-EOM
    Cuckoo implements simple, distributed cron using locks in Redis.
    This is a placeholder, as the functionality does not currently exist.

    See also:
    - zhong (https://rubygems.org/gems/zhong)
  EOM
  spec.homepage      = 'https://github.com/ab/cuckoo'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 0.52'
  spec.add_development_dependency 'yard'

  spec.required_ruby_version = '>= 2.3'
end
