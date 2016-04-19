require File.expand_path('../spec_helper', __FILE__)
require 'json'
require 'pathname'

module Molinillo
  FIXTURE_DIR = Pathname.new('spec/resolver_integration_specs')
  FIXTURE_INDEX_DIR = FIXTURE_DIR + 'index'
  FIXTURE_CASE_DIR = FIXTURE_DIR + 'case'

  class TestCase
    require File.expand_path('../spec_helper/index', __FILE__)
    require File.expand_path('../spec_helper/specification', __FILE__)
    require File.expand_path('../spec_helper/ui', __FILE__)

    attr_accessor :name, :requested, :base, :conflicts, :resolver, :result, :index

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
                       graph.add_edge(parent, v, dependency)
                     end
                   else
                     graph.add_vertex(name, dependency, true)
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
  end

  describe Resolver do
    describe 'dependency resolution' do
      Dir.glob(FIXTURE_CASE_DIR + '**/*.json').map do |fixture|
        test_case = TestCase.new(fixture)
        it test_case.name do
          resolve = lambda { test_case.resolver.resolve(test_case.requested, test_case.base) }

          if test_case.conflicts.any?
            expect { resolve.call }.to raise_error do |error|
              expect(error).to be_a(ResolverError)
              names = case error
                      when CircularDependencyError
                        error.dependencies.map(&:name)
                      when VersionConflict
                        error.conflicts.keys
                      end.to_set
              expect(names).to eq(test_case.conflicts)
            end
          else
            result = resolve.call

            pretty_dependencies = lambda do |dg|
              dg.vertices.values.map { |v| "#{v.name} (#{v.payload && v.payload.version})" }
            end
            expect(pretty_dependencies.call(result)).to contain_exactly(*pretty_dependencies.call(test_case.result))

            expect(result).to eq(test_case.result)
          end
        end
      end
    end

    describe 'in general' do
      before do
        @resolver = described_class.new(TestIndex.new('awesome'), TestUI.new)
      end

      it 'can resolve a list of 0 requirements' do
        expect(@resolver.resolve([], DependencyGraph.new)).to eq(DependencyGraph.new)
      end

      it 'includes the source of a user-specified unsatisfied dependency' do
        expect do
          @resolver.resolve([VersionKit::Dependency.new('missing', '3.0')], DependencyGraph.new)
        end.to raise_error(VersionConflict, /required by `user-specified dependency`/)
      end

      it 'can handle when allow_missing? returns true for the only requirement' do
        dep = VersionKit::Dependency.new('missing', '3.0')
        allow(@resolver.specification_provider).to receive(:allow_missing?).with(dep).and_return(true)
        expect(@resolver.resolve([dep], DependencyGraph.new).to_a).to be_empty
      end

      it 'can handle when allow_missing? returns true for a nested requirement' do
        dep = VersionKit::Dependency.new('actionpack', '1.2.3')
        allow(@resolver.specification_provider).to receive(:allow_missing?).
          with(have_attributes(:name => 'activesupport')).and_return(true)
        allow(@resolver.specification_provider).to receive(:search_for).
          with(have_attributes(:name => 'activesupport')).and_return([])
        allow(@resolver.specification_provider).to receive(:search_for).
          with(have_attributes(:name => 'actionpack')).and_call_original
        resolved = @resolver.resolve([dep], DependencyGraph.new)
        expect(resolved.map(&:payload).map(&:to_s)).to eq(['actionpack (1.2.3)'])
      end

      # Regression test. See: https://github.com/CocoaPods/Molinillo/pull/38
      it 'can resolve when swapping children with successors' do
        swap_child_with_successors_index = Class.new(TestIndex) do
          # The bug we want to write a regression test for only occurs when
          # Molinillo processes dependencies in a specific order for the given
          # index and demands. This sorting logic ensures we hit the repro case
          # when using the index file "swap_child_with_successors"
          def sort_dependencies(dependencies, activated, conflicts)
            dependencies.sort_by do |dependency|
              name = name_for(dependency)
              [
                activated.vertex_named(name).payload ? 0 : 1,
                conflicts[name] ? 0 : 1,
                activated.vertex_named(name).payload ? 0 : versions_of(name),
              ]
            end
          end

          def versions_of(dependency_name)
            specs[dependency_name].count
          end
        end

        index = swap_child_with_successors_index.new('swap_child_with_successors')
        @resolver = described_class.new(index, TestUI.new)
        demands = [
          VersionKit::Dependency.new('build-essential', '>= 0.0.0'),
          VersionKit::Dependency.new('nginx', '>= 0.0.0'),
        ]

        resolved = @resolver.resolve(demands, DependencyGraph.new)

        expected = [
          'build-essential (2.4.0)',
          '7-zip (1.0.0)',
          'windows (1.39.2)',
          'chef-handler (1.3.0)',
          'nginx (2.7.6)',
          'yum-epel (0.6.6)',
          'yum (3.10.0)',
        ]

        expect(resolved.map(&:payload).map(&:to_s)).to match_array(expected)
      end
    end
  end
end
