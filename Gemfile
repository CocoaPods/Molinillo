source 'https://rubygems.org'

gemspec

group :development do
  gem 'rspec'
  gem 'kicker'
  gem 'version_kit', :git => 'https://github.com/CocoaPods/VersionKit.git', :branch => 'master'

  # Ruby 1.8.7 fixes
  gem 'mime-types', '< 2.0'
  gem 'json_pure', '~> 1.8'

  install_if RUBY_VERSION >= '2.0.0' && Bundler.current_ruby.mri? do
    gem 'codeclimate-test-reporter', :require => false
    gem 'inch_by_inch'
    gem 'rubocop'
  end
end
