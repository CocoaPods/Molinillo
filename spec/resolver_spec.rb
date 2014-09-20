require File.expand_path('../spec_helper', __FILE__)
require 'json'
require 'pathname'

module Resolver
  FIXTURE_DIR = Pathname.new('spec/resolver_integration_specs')
  FIXTURE_INDEX_DIR = FIXTURE_DIR + 'index'
  FIXTURE_CASE_DIR = FIXTURE_DIR + 'case'

  class TestUI; include UI; end

  class TestSpecification
    attr_accessor :name, :version, :dependencies
    def initialize(hash)
      self.name = hash['name']
      self.version = VersionKit::Version.new(hash['version'])
      self.dependencies = hash['dependencies'].map do |(name, requirement)|
        VersionKit::Dependency.new(name, requirement)
      end
    end

    def ==(other)
      name == other.name &&
        version == other.version &&
        dependencies == other.dependencies
    end

    def to_s
      "#{name} (#{version})"
    end
  end

  class TestIndex
    attr_accessor :specs
    include ::Resolver::SpecificationProvider

    def initialize(fixture_name)
      File.open(FIXTURE_INDEX_DIR + (fixture_name + '.json'), 'r') do |fixture|
        self.specs = JSON.load(fixture).reduce(Hash.new([])) do |specs_by_name, (name, versions)|
          specs_by_name.tap do |specs|
            specs[name] = versions.map { |s| TestSpecification.new s }.sort { |x, y| x.version <=> y.version }
          end
        end
      end
    end

    def requirement_satisfied_by?(requirement, _activated, spec)
      case requirement
      when TestSpecification
        VersionKit::Dependency.new(requirement.name, requirement.version).satisfied_by?(spec.version)
      when VersionKit::Dependency
        requirement.satisfied_by?(spec.version)
      end
    end

    def search_for(dependency)
      includes_pre_release = dependency.requirement_list.requirements.any? do |r|
        VersionKit::Version.new(r.reference_version).pre_release?
      end
      specs[dependency.name].reject do |spec|
        includes_pre_release ? false : spec.version.pre_release?
      end
    end

    def name_for_dependency(dependency)
      dependency.name
    end

    def dependencies_for(dependency)
      dependency.dependencies
    end

    def sort_dependencies(dependencies)
      dependencies.sort { |x, y| x.name <=> y.name }
    end
  end

  class TestCase
    attr_accessor :name, :requested, :base, :conflicts, :resolver, :result, :index

    # rubocop:disable Metrics/MethodLength
    def initialize(fixture_path)
      File.open(fixture_path) do |fixture|
        JSON.load(fixture).tap do |test_case|
          self.name = test_case['name']
          self.index = TestIndex.new(test_case['index'] || 'awesome')
          self.requested = test_case['requested'].map do |(name, reqs)|
            VersionKit::Dependency.new name, reqs.split(',').map(&:chomp)
          end
          add_dependencies_to_graph = lambda do |graph, parent, hash|
            name = hash['name']
            version = VersionKit::Version.new(hash['version'])
            dependency = index.specs[name].find { |s| s.version == version }
            node = if parent
                     graph.add_vertex(name, dependency).tap do |v|
                       graph.add_edge(parent, v)
                     end
                   else
                     graph.add_root_vertex(name, dependency)
                   end
            hash['dependencies'].each do |dep|
              add_dependencies_to_graph.call(graph, node, dep)
            end
          end
          self.result = test_case['resolved'].reduce(DependencyGraph.new) do |graph, r|
            graph.tap do |g|
              add_dependencies_to_graph.call(g, nil, r)
            end
          end
          self.base = test_case['base'].reduce(DependencyGraph.new) do |graph, r|
            graph.tap do |g|
              add_dependencies_to_graph.call(g, nil, r)
            end
          end
          self.conflicts = test_case['conflicts'].to_set
        end
      end

      self.resolver = Resolver.new(index, TestUI.new)
    end
    # rubocop:enable Metrics/MethodLength
  end

  describe Resolver do

    describe 'dependency resolution' do
      Dir.glob(FIXTURE_CASE_DIR + '**/*.json').map do |fixture|
        test_case = TestCase.new(fixture)
        it test_case.name do
          resolve = lambda { test_case.resolver.resolve(test_case.requested, test_case.base) }

          if test_case.conflicts.any?
            should.raise ResolverError do
              resolve.call
            end.dependencies.map(&:name).to_set.should.equal test_case.conflicts
          else
            result = resolve.call

            pretty_dependencies = lambda do |dg|
              dg.vertices.values.map { |v| "#{v.payload.name} (#{v.payload.version})" }.sort
            end
            pretty_dependencies.call(result).should.
              equal pretty_dependencies.call(test_case.result)

            result.should.equal test_case.result
          end
        end
      end
    end

  end
end
