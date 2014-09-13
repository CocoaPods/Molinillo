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
  if RUBY_VERSION >= '1.9.3'
    gem 'rubocop'
  end
end
