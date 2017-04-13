# frozen_string_literal: true
require File.expand_path('../spec_helper', __FILE__)

module Molinillo
  FIXTURE_CASE_DIR = FIXTURE_DIR + 'case'

  class TestCase
    attr_accessor :name, :requested, :base, :conflicts, :result, :index

    def initialize(fixture_path)
      File.open(fixture_path) do |fixture|
        JSON.load(fixture).tap do |test_case|
          self.name = test_case['name']
          self.index = TestIndex.from_fixture(test_case['index'] || 'awesome')
          self.requested = test_case['requested'].map do |(name, reqs)|
            Gem::Dependency.new name.delete("\x01"), reqs.split(',').map(&:chomp)
          end
          add_dependencies_to_graph = lambda do |graph, parent, hash|
            name = hash['name']
            version = Gem::Version.new(hash['version'])
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
    end

    def run(index_class, context)
      return if ignore?(index_class)

      test_case = self

      context.instance_eval do
        it test_case.name do
          resolve = lambda do
            index = index_class.new(test_case.index.specs)
            resolver = Resolver.new(index, TestUI.new)
            resolver.resolve(test_case.requested, test_case.base)
          end

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

            expect(result).to equal_dependency_graph(test_case.result)
          end
        end
      end
    end

    def ignore?(index_class)
      if name == 'can resolve when two specs have the same dependencies and swapping happens'
        if index_class == BerkshelfIndex &&
          Gem.ruby_version < Gem::Version.new('2.3')

          # That index doesn't do a great job sorting, and segiddins has been
          # unable to get the test passing with the bad sort (on Ruby < 2.3)
          # without breaking other specs
          return true
        end

        # These indexes don't sort to minimize conflicts, so a deep dependency
        # tree is too slow with them.
        if index_class == TestIndex || index_class == ReverseBundlerIndex
          return true
        end

        #TODO figure out what to do with this
        return true if index_class == BerkshelfIndex
      end

      if name == 'deep conflicts with duplicate dependencies'
        return true if index_class == ReverseBundlerIndex
        #TODO figure out what to do with this
        return true if index_class == BerkshelfIndex
      end

      false
    end

    def self.save!(path, name, index, requirements, resolved)
      resolved_to_h = proc do |v|
        { :name => v.name, :version => v.payload.version, :dependencies => v.successors.map(&resolved_to_h) }
      end
      resolved = resolved.vertices.reduce([]) do |array, (_n, v)|
        if v.root
          array << resolved_to_h.call(v)
        else
          array
        end
      end

      File.open(File.join(FIXTURE_CASE_DIR, "#{path}.json"), 'w') do |f|
        f.write JSON.pretty_generate(
          :name => name,
          :index => index,
          :requested => Hash[requirements.map { |r| [r.name, r.requirement.to_s] }],
          :base => [],
          :resolved => resolved.sort_by { |v| v[:name] },
          :conflicts => []
        )
      end
    end
  end

  describe Resolver do
    describe 'dependency resolution' do
      test_cases = Dir.glob(FIXTURE_CASE_DIR + '**/*.json').map { |fixture| TestCase.new(fixture) }
      INDICES.each do |index_class|
        context "with the #{index_class.to_s.split('::').last} index" do
          test_cases.each { |tc| tc.run(index_class, self) }
        end
      end
    end

    describe 'in general' do
      before do
        @resolver = described_class.new(TestIndex.from_fixture('awesome'), TestUI.new)
      end

      it 'includes the source of a user-specified unsatisfied dependency' do
        expect do
          @resolver.resolve([Gem::Dependency.new('missing', '3.0')], DependencyGraph.new)
        end.to raise_error(VersionConflict, /required by `user-specified dependency`/)
      end

      it 'can handle when allow_missing? returns true for the only requirement' do
        dep = Gem::Dependency.new('missing', '3.0')
        allow(@resolver.specification_provider).to receive(:allow_missing?).with(dep).and_return(true)
        expect(@resolver.resolve([dep], DependencyGraph.new).to_a).to be_empty
      end

      it 'can handle when allow_missing? returns true for a nested requirement' do
        dep = Gem::Dependency.new('actionpack', '1.2.3')
        allow(@resolver.specification_provider).to receive(:allow_missing?).
          with(have_attributes(:name => 'activesupport')).and_return(true)
        allow(@resolver.specification_provider).to receive(:search_for).
          with(have_attributes(:name => 'activesupport')).and_return([])
        allow(@resolver.specification_provider).to receive(:search_for).
          with(have_attributes(:name => 'actionpack')).and_call_original
        resolved = @resolver.resolve([dep], DependencyGraph.new)
        expect(resolved.map(&:payload).map(&:to_s)).to eq(['actionpack (1.2.3)'])
      end

      it 'only cleans up orphaned nodes after swapping' do
        index = TestIndex.new(
          'a' => [
            TestSpecification.new('name' => 'a', 'version' => '1.0.0', 'dependencies' => { 'z' => '= 2.0.0' }),
            TestSpecification.new('name' => 'a', 'version' => '2.0.0', 'dependencies' => { 'z' => '= 1.0.0' }),
          ],
          'b' => [
            TestSpecification.new('name' => 'b', 'version' => '1.0.0', 'dependencies' => { 'a' => '< 2' }),
            TestSpecification.new('name' => 'b', 'version' => '2.0.0', 'dependencies' => { 'a' => '< 2' }),
          ],
          'c' => [
            TestSpecification.new('name' => 'c', 'version' => '1.0.0'),
            TestSpecification.new('name' => 'c', 'version' => '2.0.0', 'dependencies' => { 'b' => '< 2' }),
          ],
          'z' => [
            TestSpecification.new('name' => 'z', 'version' => '1.0.0'),
            TestSpecification.new('name' => 'z', 'version' => '2.0.0'),
          ]
        )
        def index.sort_dependencies(dependencies, _activated, _conflicts)
          index = ['c (>= 1.0.0)', 'b (< 2.0.0)', 'a (< 2.0.0)', 'c (= 1.0.0)']
          dependencies.sort_by do |dep|
            [
              index.index(dep.to_s) || 999,
            ]
          end
        end
        @resolver = described_class.new(index, TestUI.new)
        demands = [
          Gem::Dependency.new('c', '= 1.0.0'),
          Gem::Dependency.new('c', '>= 1.0.0'),
          Gem::Dependency.new('z', '>= 1.0.0'),
        ]

        resolved = @resolver.resolve(demands, DependencyGraph.new)

        expected = [
          'c (1.0.0)',
          'z (2.0.0)',
        ]

        expect(resolved.map(&:payload).map(&:to_s)).to match_array(expected)
      end

      it 'does not reset parent tracking after swapping when another requirement led to the child' do
        demands = [
          Gem::Dependency.new('autobuild'),
          Gem::Dependency.new('pastel'),
          Gem::Dependency.new('tty-prompt'),
          Gem::Dependency.new('tty-table'),
        ]

        index = BundlerIndex.from_fixture('rubygems-2017-01-24')
        index.specs['autobuild'] = [
          TestSpecification.new('name' => 'autobuild',
                                'version' => '0.1.0',
                                'dependencies' => {
                                  'tty-prompt' => '>= 0.6.0, ~> 0.6.0',
                                  'pastel' => '>= 0.6.0, ~> 0.6.0',
                                }),
        ]

        @resolver = described_class.new(index, TestUI.new)
        demands.each { |d| index.search_for(d) }

        resolved = @resolver.resolve(demands, DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s).sort).to include('pastel (0.6.1)', 'tty-table (0.6.0)')
      end
    end
  end
end
