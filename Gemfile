source 'https://rubygems.org'

gemspec

group :development do
  gem 'bacon'
  gem 'mocha', '~> 0.11.4'
  gem 'mocha-on-bacon'
  gem 'prettybacon'
  gem 'kicker'
  gem 'version_kit', :git => 'https://github.com/CocoaPods/VersionKit.git'

  # Ruby 1.8.7 fixes
  gem 'mime-types', '< 2.0'
  gem 'json_pure', '~> 1.8'
  if RUBY_VERSION >= '2.0.0'
    gem 'rubocop'
    gem 'codeclimate-test-reporter', :require => false
  end
end
