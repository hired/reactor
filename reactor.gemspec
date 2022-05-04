# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'reactor/version'

Gem::Specification.new do |spec|
  spec.name          = 'reactor'
  spec.version       = Reactor::VERSION
  spec.authors       = %w[winfred walt nate petermin christospappas therabidbanana]
  spec.email         = ['gabe@hired.com', 'christos@hired.com']
  spec.description   = 'rails chrono reactor'
  spec.summary       = 'Sidekiq/ActiveRecord pubsub lib'
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '> 5.2', '< 6.1'
  spec.add_dependency 'sidekiq', '> 4.0', '< 6.0'

  spec.add_development_dependency 'appraisal'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-its'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'sqlite3'
end
