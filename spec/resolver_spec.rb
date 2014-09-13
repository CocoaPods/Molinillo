require File.expand_path('../spec_helper', __FILE__)
require 'json'
require 'pathname'

module VersionKit
  describe Resolver do

    FIXTURE_DIR = Pathname.new('resolver_integration_specs')
    FIXTURE_INDEX_DIR = FIXTURE_DIR + 'index'
    FIXTURE_CASE_DIR = FIXTURE_DIR + 'case'

    class TestSpecification
      attr_accessor :name, :version, :dependencies, :platform
      def initialize(hash)
        self.name = hash['name']
        self.version = hash['version']
        self.dependencies = hash['dependencies']
        self.platform = hash['platform']
      end
    end

    class TestIndex
      attr_accessor :specs

      def initialize(fixture_name)
        File.open(FIXTURE_INDEX_DIR + (fixture_name + '.json'), 'r') do |fixture|
          self.specs = JSON.load(fixture).reduce({}) do |specs_by_name, (name, versions)|
            specs_by_name.tap do |specs|
              specs[name] = versions.map { |s| TestSpecification.new s }
            end
          end
        end
      end
    end

    class TestCase
      attr_accessor :name, :requested, :resolver, :result, :index

      # rubocop:disable Metrics/MethodLength
      def initialize(fixture_path)
        File.open(fixture_path) do |fixture|
          JSON.load(fixture).tap do |test_case|
            self.name = test_case['name']
            self.requested = test_case['requested'].map do |(name, reqs)|
              Dependency.new name, reqs.split(/\w/)
            end
            self.result = Resolver::Result.new(test_case['resolved'], test_case['conflicts'])
            self.index = TestIndex.new(test_case['index'] || 'awesome')
          end
        end

        self.resolver = Resolver.new
      end
      # rubocop:enable Metrics/MethodLength
    end

    describe 'dependency resolution' do
      Dir.glob(FIXTURE_CASE_DIR + '**/*.json').map do |fixture|
        test_case = TestCase.new(fixture)
        it test_case.name do
          test_case.resolver.resolve.should.equal test_case.result
        end
      end
    end

  end
end
