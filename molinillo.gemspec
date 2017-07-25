# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'molinillo/gem_metadata'

Gem::Specification.new do |spec|
  spec.name          = 'molinillo'
  spec.version       = Molinillo::VERSION
  spec.authors       = ['Samuel E. Giddins']
  spec.email         = ['segiddins@segiddins.me']
  spec.summary       = 'Provides support for dependency resolution'
  spec.homepage      = 'https://github.com/CocoaPods/Molinillo'
  spec.license       = 'MIT'

  spec.files         = Dir['lib/**/*.rb', '*.md', 'LICENSE']
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.5'
  spec.add_development_dependency 'rake'
end
