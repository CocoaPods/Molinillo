# frozen_string_literal: true
require File.expand_path('../spec_helper', __FILE__)

module Molinillo
  FIXTURE_CASE_DIR = FIXTURE_DIR + 'case'

  class TestCase
    attr_accessor :name, :requested, :base, :conflicts, :resolver, :result, :index

    def initialize(fixture_path)
      File.open(fixture_path) do |fixture|
        JSON.load(fixture).tap do |test_case|
          self.name = test_case['name']
          self.index = TestIndex.from_fixture(test_case['index'] || 'awesome')
          self.requested = test_case['requested'].map do |(name, reqs)|
            Gem::Dependency.new name, reqs.split(',').map(&:chomp)
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
        @resolver = described_class.new(TestIndex.from_fixture('awesome'), TestUI.new)
      end

      it 'can resolve a list of 0 requirements' do
        expect(@resolver.resolve([], DependencyGraph.new)).to eq(DependencyGraph.new)
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

      it 'can resolve when two specs have the same dependencies' do
        index = BundlerIndex.from_fixture('rubygems-2016-09-11')
        @resolver = described_class.new(index, TestUI.new)
        demands = [
          Gem::Dependency.new('chef', '~> 12.1.2'),
        ]

        demands.each { |d| index.search_for(d) }
        resolved = @resolver.resolve(demands, DependencyGraph.new)

        expected = [
          'rake (10.5.0)',
          'builder (3.2.2)',
          'ffi (1.9.14)',
          'libyajl2 (1.2.0)',
          'hashie (2.1.2)',
          'mixlib-log (1.7.1)',
          'rack (2.0.1)',
          'uuidtools (2.1.5)',
          'diff-lcs (1.2.5)',
          'erubis (2.7.0)',
          'highline (1.7.8)',
          'mixlib-cli (1.7.0)',
          'mixlib-config (2.2.4)',
          'mixlib-shellout (2.2.7)',
          'net-ssh (2.9.4)',
          'ipaddress (0.8.3)',
          'mime-types (2.99.3)',
          'systemu (2.6.5)',
          'wmi-lite (1.0.0)',
          'plist (3.1.0)',
          'coderay (1.1.1)',
          'method_source (0.8.2)',
          'slop (3.6.0)',
          'rspec-support (3.5.0)',
          'multi_json (1.12.1)',
          'net-telnet (0.1.1)',
          'sfl (2.2)',
          'ffi-yajl (1.4.0)',
          'mixlib-authentication (1.4.1)',
          'net-ssh-gateway (1.2.0)',
          'net-scp (1.2.1)',
          'pry (0.10.4)',
          'rspec-core (3.5.3)',
          'rspec-expectations (3.5.0)',
          'rspec-mocks (3.5.0)',
          'chef-zero (4.2.3)',
          'ohai (8.4.0)',
          'net-ssh-multi (1.2.1)',
          'specinfra (2.61.3)',
          'rspec_junit_formatter (0.2.3)',
          'rspec-its (1.2.0)',
          'rspec (3.5.0)',
          'serverspec (2.36.1)',
          'chef (12.1.2)',
        ]

        expect(resolved.map(&:payload).map(&:to_s)).to match_array(expected)
      end

      it 'can resolve when two specs have the same dependencies and swapping happens' do
        index = BundlerIndex.from_fixture('rubygems-2016-10-06')
        @resolver = described_class.new(index, TestUI.new)
        demands = [
          Gem::Dependency.new('avro_turf', '0.6.2'),
          Gem::Dependency.new('fog', '1.38.0'),
        ]
        demands.each { |d| index.search_for(d) }

        resolved = @resolver.resolve(demands, DependencyGraph.new)

        expected = [
          'pkg-config (1.1.7)',
          'CFPropertyList (2.3.3)',
          'multi_json (1.12.1)',
          'excon (0.45.4)',
          'builder (3.2.2)',
          'formatador (0.2.5)',
          'ipaddress (0.8.3)',
          'xml-simple (1.1.5)',
          'mini_portile2 (2.1.0)',
          'inflecto (0.0.2)',
          'trollop (2.1.2)',
          'fission (0.5.0)',
          'avro (1.8.1)',
          'fog-core (1.37.0)',
          'nokogiri (1.6.8)',
          'avro_turf (0.6.2)',
          'fog-json (1.0.2)',
          'fog-local (0.3.0)',
          'fog-vmfusion (0.1.0)',
          'fog-xml (0.1.2)',
          'rbvmomi (1.8.2)',
          'fog-aliyun (0.1.0)',
          'fog-brightbox (0.11.0)',
          'fog-sakuracloud (1.7.5)',
          'fog-serverlove (0.1.2)',
          'fog-softlayer (1.1.4)',
          'fog-storm_on_demand (0.1.1)',
          'fog-atmos (0.1.0)',
          'fog-aws (0.9.2)',
          'fog-cloudatcost (0.1.2)',
          'fog-dynect (0.0.3)',
          'fog-ecloud (0.3.0)',
          'fog-google (0.1.0)',
          'fog-openstack (0.1.3)',
          'fog-powerdns (0.1.1)',
          'fog-profitbricks (0.0.5)',
          'fog-rackspace (0.1.1)',
          'fog-radosgw (0.0.5)',
          'fog-riakcs (0.1.0)',
          'fog-terremark (0.1.0)',
          'fog-voxel (0.1.0)',
          'fog-xenserver (0.2.3)',
          'fog-vsphere (1.2.0)',
          'fog (1.38.0)',
        ]

        expect(resolved.map(&:payload).map(&:to_s).sort).to eq(expected.sort)
      end

      it 'can unwind when the conflict has a common parent' do
        index = BundlerIndex.from_fixture('rubygems-2016-11-05')
        @resolver = described_class.new(index, TestUI.new)
        demands = [
          Gem::Dependency.new('github-pages', '>= 0'),
        ]
        demands.each { |d| index.search_for(d) }

        resolved = @resolver.resolve(demands, DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s).sort).to include('github-pages (104)')
      end

      it 'can resolve when swapping changes transitive dependencies' do
        index = TestIndex.from_fixture('restkit')
        def index.sort_dependencies(dependencies, activated, conflicts)
          dependencies.sort_by do |d|
            [
              activated.vertex_named(d.name).payload ? 0 : 1,
              dependency_prerelease?(d) ? 0 : 1,
              conflicts[d.name] ? 0 : 1,
              search_for(d).count,
            ]
          end
        end

        def index.requirement_satisfied_by?(requirement, activated, spec)
          existing_vertices = activated.vertices.values.select do |v|
            v.name.split('/').first == requirement.name.split('/').first
          end
          existing = existing_vertices.map(&:payload).compact.first
          if existing
            existing.version == spec.version && requirement.requirement.satisfied_by?(spec.version)
          else
            requirement.requirement.satisfied_by? spec.version
          end
        end

        @resolver = described_class.new(index, TestUI.new)
        demands = [
          Gem::Dependency.new('RestKit', '~> 0.23.0'),
          Gem::Dependency.new('RestKit', '<= 0.23.2'),
        ]

        resolved = @resolver.resolve(demands, DependencyGraph.new)

        expected = [
          'RestKit (0.23.2)',
          'RestKit/Core (0.23.2)',
        ]

        expect(resolved.map(&:payload).map(&:to_s)).to match_array(expected)
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
            Array(specs[dependency_name]).count
          end
        end

        index = swap_child_with_successors_index.from_fixture('swap_child_with_successors')
        @resolver = described_class.new(index, TestUI.new)
        demands = [
          Gem::Dependency.new('build-essential', '>= 0.0.0'),
          Gem::Dependency.new('nginx', '>= 0.0.0'),
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

      it 'can resolve ur face' do
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
    end
  end
end
