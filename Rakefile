# encoding: utf-8

#-- Bootstrap --------------------------------------------------------------#

desc 'Initializes your working copy to run the specs'
task :bootstrap do
  if system('which bundle')
    title 'Installing gems'
    sh 'bundle install'

    title 'Updating submodule'
    sh 'git submodule update --init'
  else
    $stderr.puts "\033[0;31m" \
      "[!] Please install the bundler gem manually:\n" \
      '    $ [sudo] gem install bundler' \
      "\e[0m"
    exit 1
  end
end

begin
  require 'bundler/gem_tasks'

  ENABLE_RUBOCOP = Bundler.current_ruby.mri? && RUBY_VERSION >= '2.0.0'

  default_tasks = [:spec]
  default_tasks << :rubocop if ENABLE_RUBOCOP
  task :default => default_tasks

  #-- Specs ------------------------------------------------------------------#

  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new

  #-- Kick -------------------------------------------------------------------#

  desc 'Automatically run specs for updated files'
  task :kick do
    exec 'bundle exec kicker -c'
  end

  #-- RuboCop ----------------------------------------------------------------#

  if ENABLE_RUBOCOP
    require 'rubocop/rake_task'
    RuboCop::RakeTask.new
  end

rescue LoadError => e
  $stderr.puts "\033[0;31m" \
    '[!] Some Rake tasks haven been disabled because the environment' \
    ' couldn’t be loaded. Be sure to run `rake bootstrap` first.' \
    "\e[0m"
  $stderr.puts e.message
  $stderr.puts e.backtrace
  $stderr.puts
end

#-- Helpers ------------------------------------------------------------------#

def title(title)
  cyan_title = "\033[0;36m#{title}\033[0m"
  puts
  puts '-' * 80
  puts cyan_title
  puts '-' * 80
  puts
end
