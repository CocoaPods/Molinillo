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

  default_tasks = [:spec]

  #-- Specs ------------------------------------------------------------------#

  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new

  #-- Kick -------------------------------------------------------------------#

  desc 'Automatically run specs for updated files'
  task :kick do
    exec 'bundle exec kicker -c'
  end

  #-- RuboCop ----------------------------------------------------------------#

  if Bundler.rubygems.loaded_specs('rubocop')
    require 'rubocop/rake_task'
    RuboCop::RakeTask.new
    default_tasks << :rubocop
  end

  #-- Inch -------------------------------------------------------------------#

  if Bundler.rubygems.loaded_specs('inch_by_inch')
    require 'inch_by_inch/rake_task'
    InchByInch::RakeTask.new do |task|
      task.failing_grades << :U
    end
    default_tasks << :inch
  end

  #-- Default ----------------------------------------------------------------#

  task :default => default_tasks

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
