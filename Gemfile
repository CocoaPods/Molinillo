# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development do
  gem 'kicker'
  gem 'rspec'

  # Ruby 1.8.7 fixes
  gem 'json_pure', '~> 1.8'
  gem 'mime-types', '< 2.0'

  install_if RUBY_VERSION >= '2.0.0' && Bundler.current_ruby.mri? do
    gem 'codeclimate-test-reporter', :require => false
    gem 'inch_by_inch'
    gem 'rubocop'
  end
end
