require 'bundler/setup'

# Set up coverage analysis
#-----------------------------------------------------------------------------#

if (ENV['CI'] || ENV['GENERATE_COVERAGE']) && RUBY_VERSION >= '2.0.0' && Bundler.current_ruby.mri?
  require 'simplecov'
  require 'codeclimate-test-reporter'

  if ENV['CI']
    SimpleCov.formatter = CodeClimate::TestReporter::Formatter
  elsif ENV['GENERATE_COVERAGE']
    SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
  end
  SimpleCov.start do
    add_filter '/vendor/'
    add_filter '/lib/molinillo/modules/'
  end
  CodeClimate::TestReporter.start
end

# Set up
#-----------------------------------------------------------------------------#

require 'pathname'
ROOT = Pathname.new(File.expand_path('../../', __FILE__))
$LOAD_PATH.unshift((ROOT + 'lib').to_s)
$LOAD_PATH.unshift((ROOT + 'spec').to_s)

require 'version_kit'
require 'molinillo'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
end
