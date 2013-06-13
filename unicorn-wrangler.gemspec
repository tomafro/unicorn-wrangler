# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'unicorn/wrangler/version'

Gem::Specification.new do |spec|
  spec.name          = "unicorn-wrangler"
  spec.version       = Unicorn::Wrangler::VERSION
  spec.authors       = ["Tom Ward"]
  spec.email         = ["tom@popdog.net"]
  spec.description   = %q{Wrangles unicorns}
  spec.summary       = %q{Helps manage unicorn processes}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "unicorn"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "curb"
end
