# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'reactor/version'

Gem::Specification.new do |spec|
  spec.name          = "reactor"
  spec.version       = Reactor::VERSION
  spec.authors       = ["winfred", "walt", "nate", "petermin"]
  spec.email         = ["winfred@hired.com", "walt@hired.com", "nate@hired.com", "kengteh.min@gmail.com"]
  spec.description   = %q{ rails chrono reactor }
  spec.summary       = %q{ ActiveJob/ActiveRecord pubsub lib }
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'activejob', '~> 4.2'
  spec.add_dependency 'activerecord', '~> 4.2'

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.2.0"
  spec.add_development_dependency "rspec-its"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "test_after_commit"
end
