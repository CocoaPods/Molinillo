# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development do
  gem 'kicker'
  gem 'rspec'

  install_if Bundler.current_ruby.mri? do
    gem 'codeclimate-test-reporter', :require => false
    gem 'inch_by_inch'
    gem 'rubocop'
  end
end
