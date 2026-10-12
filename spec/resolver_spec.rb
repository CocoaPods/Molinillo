# frozen_string_literal: true

require File.expand_path('../spec_helper', __FILE__)

module Molinillo
  FIXTURE_CASE_DIR = FIXTURE_DIR + 'case'

  class TestCase
    attr_accessor :name

    def self.from_fixture(fixture_path)
      fixture = File.open(fixture_path) { |f| JSON.load(f) }
      new(fixture)
    end

    def initialize(fixture)
      @fixture = fixture
      self.name = fixture['name']
    end

    def index
      @index ||= TestIndex.from_fixture(@fixture['index'] || 'awesome')
    end

    def requested
      @requested ||= @fixture['requested'].map do |(name, reqs)|
        Gem::Dependency.new name.delete("\x01"), reqs.split(',').map(&:chomp)
      end
    end

    def add_dependencies_to_graph(graph, parent, hash, all_parents = Set.new)
      name = hash['name']
      version = Gem::Version.new(hash['version'])
      dependency = index.specs[name].find { |s| s.version == version }
      vertex = if parent
                 graph.add_vertex(name, dependency).tap do |v|
                   graph.add_edge(parent, v, dependency)
                 end
               else
                 graph.add_vertex(name, dependency, true)
               end
      return unless all_parents.add?(vertex)
      hash['dependencies'].each do |dep|
        add_dependencies_to_graph(graph, vertex, dep, all_parents)
      end
    end

    def result
      @result ||= @fixture['resolved'].reduce(DependencyGraph.new) do |graph, r|
        graph.tap do |g|
          add_dependencies_to_graph(g, nil, r)
        end
      end
    end

    def base
      @base ||= @fixture['base'].reduce(DependencyGraph.new) do |graph, r|
        graph.tap do |g|
          add_dependencies_to_graph(g, nil, r)
        end
      end
    end

    def conflicts
      @conflicts ||= @fixture['conflicts'].to_set
    end

    def self.all
      @all ||= Dir.glob(FIXTURE_CASE_DIR + '**/*.json').map { |fixture| TestCase.from_fixture(fixture) }
    end

    def resolve(index_class)
      index = index_class.new(self.index.specs)
      resolver = Resolver.new(index, TestUI.new)
      resolver.resolve(requested, base)
    end

    def run(index_class, context)
      test_case = self

      context.instance_eval do
        it test_case.name do
          skip 'does not yet reliably pass' if test_case.ignore?(index_class)

          if test_case.conflicts.any?
            expect { test_case.resolve(index_class) }.to raise_error do |error|
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
            result = test_case.resolve(index_class)

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
      if index_class == RandomSortIndex && name == 'resolves a conflict which requires non-trivial unwinding'

        # This index occassionally finds orders that are *incredibly* slow to resolve,
        # and greysteil hasn't found a way to speed it up yet.
        return true
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
      INDICES.each do |index_class|
        context "with the #{index_class.to_s.split('::').last} index" do
          TestCase.all.each { |tc| tc.run(index_class, self) }
        end
      end
    end

    describe 'in general' do
      before do
        @resolver = described_class.new(TestIndex.from_fixture('awesome'), TestUI.new)
      end

      it 'includes the source of a user-specified unsatisfied dependency' do
        expect { @resolver.resolve([Gem::Dependency.new('missing', '3.0')], DependencyGraph.new) }.
          to raise_error(VersionConflict) do |conflict|
          expect(conflict.message).to eq <<-EOS.strip
Unable to satisfy the following requirements:

- `missing (= 3.0)` required by `user-specified dependency`
          EOS
          expect(conflict.message_with_trees).to eq <<-EOS.strip
Molinillo could not find compatible versions for possibility named "missing":
  In user-specified dependency:
    missing (= 3.0)
          EOS
        end
      end

      it 'raises conflicts with requirement trees' do
        test_case = TestCase.all.find { |tc| tc.name == 'yields conflicts if a child dependency is not resolved' }
        index_class = TestIndex

        expect { test_case.resolve(index_class) }.to raise_error(VersionConflict) do |conflict|
          expect(conflict.message).to eq <<-EOS.strip
Unable to satisfy the following requirements:

- `json (>= 1.7.7)` required by `berkshelf (2.0.7)`
- `json (<= 1.7.7, >= 1.4.4)` required by `chef (10.26)`
          EOS
          expect(conflict.message_with_trees(:version_for_spec => lambda(&:version))).to eq <<-EOS.strip
Molinillo could not find compatible versions for possibility named "json":
  In user-specified dependency:
    chef_app_error (>= 0) was resolved to 1.0.0, which depends on
      berkshelf (~> 2.0) was resolved to 2.0.7, which depends on
        json (>= 1.7.7)

    chef_app_error (>= 0) was resolved to 1.0.0, which depends on
      chef (~> 10.26) was resolved to 10.26, which depends on
        json (<= 1.7.7, >= 1.4.4)
          EOS
        end
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

      it 'only cleans up orphaned vertices after swapping' do
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

      it 'includes the whole path in circular dependency errors' do
        index = TestIndex.new(
          'a' => [
            TestSpecification.new('name' => 'a', 'version' => '1.0.0', 'dependencies' => { 'b' => '= 1.0.0' }),
          ],
          'b' => [
            TestSpecification.new('name' => 'b', 'version' => '1.0.0', 'dependencies' => { 'c' => '= 1.0.0' }),
          ],
          'c' => [
            TestSpecification.new('name' => 'c', 'version' => '1.0.0', 'dependencies' => { 'd' => '= 1.0.0' }),
          ],
          'd' => [
            TestSpecification.new('name' => 'd', 'version' => '1.0.0', 'dependencies' => { 'a' => '= 1.0.0' }),
          ]
        )

        demands = [
          Gem::Dependency.new('a'),
        ]

        resolver = described_class.new(index, TestUI.new)

        expect { resolver.resolve(demands, DependencyGraph.new) }.
          to raise_error(CircularDependencyError, 'There is a circular dependency between a and b and c and d')
      end

      it 'raises a circular dependency error regardless of the order dependencies are requested' do
        index = TestIndex.new(
          'a' => [
            TestSpecification.new('name' => 'a', 'version' => '1.0.0', 'dependencies' => { 'b' => '= 1.0.0' }),
          ],
          'b' => [
            TestSpecification.new('name' => 'b', 'version' => '1.0.0', 'dependencies' => { 'c' => '= 1.0.0' }),
          ],
          'c' => [
            TestSpecification.new('name' => 'c', 'version' => '1.0.0', 'dependencies' => { 'a' => '= 1.0.0' }),
          ]
        )

        demands = [
          Gem::Dependency.new('b'),
          Gem::Dependency.new('a'),
        ]

        resolver = described_class.new(index, TestUI.new)

        expect { resolver.resolve(demands, DependencyGraph.new) }.
          to raise_error(CircularDependencyError, 'There is a circular dependency between a and b and c')
      end

      it 'raises the recorded circular dependency error once every alternative has failed' do
        # p4 (2) -> p2 (1) -> p4 is circular, and p4 (1) depends on p3, which
        # does not exist. The CircularDependencyError hit first is recorded as
        # the conflict's underlying error and must be raised once the stack is
        # exhausted, rather than re-entering conflict handling with no state.
        # p3 is absent from the index; Hash.new([]) mirrors fixture-loaded indices.
        specs = Hash.new([]).merge(
          'p2' => [
            TestSpecification.new('name' => 'p2', 'version' => '1', 'dependencies' => { 'p4' => '>= 2' }),
          ],
          'p4' => [
            TestSpecification.new('name' => 'p4', 'version' => '1', 'dependencies' => { 'p3' => '= 1' }),
            TestSpecification.new('name' => 'p4', 'version' => '2', 'dependencies' => { 'p2' => '!= 2' }),
          ]
        )
        index = TestIndex.new(specs)
        resolver = described_class.new(index, TestUI.new)

        expect { resolver.resolve([Gem::Dependency.new('p4', '>= 0')], DependencyGraph.new) }.
          to raise_error(CircularDependencyError, 'There is a circular dependency between p4 and p2')
      end

      it 'does not compare every new requirement against the whole state stack' do
        # m1..m200 each require b; nothing conflicts. Checking whether a
        # requirement already has a state used to compare it against every
        # state on the stack, i.e. O(n^2) requirement comparisons in total.
        comparisons = 0
        counting_dependency = Class.new(Gem::Dependency) do
          define_method(:==) do |other|
            comparisons += 1
            super(other)
          end
        end
        n = 200
        specs = Hash.new([])
        (1..n).each do |i|
          spec = TestSpecification.new('name' => "m#{i}", 'version' => '1')
          spec.dependencies = [counting_dependency.new('b', ">= #{i % 3}")]
          specs["m#{i}"] = [spec]
        end
        specs['b'] = %w[1 2].map { |v| TestSpecification.new('name' => 'b', 'version' => v) }
        index = TestIndex.new(specs)
        def index.sort_dependencies(dependencies, _activated, _conflicts)
          dependencies
        end

        demands = (1..n).map { |i| counting_dependency.new("m#{i}") }
        resolved = described_class.new(index, TestUI.new).resolve(demands, DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s)).to include('b (2)', 'm1 (1)', "m#{n} (1)")
        # Scanning the whole stack needs ~41_000 comparisons here.
        expect(comparisons).to be < 10 * n
      end

      it 'does not unwind exponentially when several parents share an equal requirement' do
        # a1..a10 each have versions 1..3, where a_i (j) requires `s (= j)` --
        # the same requirement for every a_i. f, processed last, requires
        # `s (= 1)`, so every a_i has to drop to version 1.
        #
        # Requirements are compared with `==` by the resolver, but `eql?` is
        # up to the provider. Bundler makes Gem::Dependency#eql? value-based
        # (so Array#uniq already collapses the duplicates); plain RubyGems
        # does not, and that identity-based `eql?` is what triggers the bug.
        identity_dependency = Class.new(Gem::Dependency) do
          def eql?(other)
            equal?(other)
          end
        end
        n = 10
        spec = lambda do |name, version, deps = {}|
          TestSpecification.new('name' => name, 'version' => version, 'dependencies' => deps).tap do |s|
            s.dependencies = s.dependencies.map { |d| identity_dependency.new(d.name, d.requirement) }
          end
        end
        specs = Hash.new([])
        (1..n).each do |i|
          specs["a#{i}"] = %w[1 2 3].map { |v| spec.call("a#{i}", v, 's' => "= #{v}") }
        end
        specs['s'] = %w[1 2 3].map { |v| spec.call('s', v) }
        specs['f'] = [spec.call('f', '1', 's' => '= 1')]
        index = TestIndex.new(specs)
        # Keep declaration order so that f's requirement is only seen after
        # every a_i has been activated at its newest version.
        def index.sort_dependencies(dependencies, _activated, _conflicts)
          dependencies
        end

        ui = TestUI.new
        def ui.progress_rate
          0.0 # report progress on every iteration
        end

        def ui.iterations
          @iterations ||= 0
        end

        def ui.indicate_progress
          @iterations = iterations + 1
        end

        demands = (1..n).map { |i| identity_dependency.new("a#{i}") } + [identity_dependency.new('f')]
        resolved = described_class.new(index, ui).resolve(demands, DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s)).
          to match_array((1..n).map { |i| "a#{i} (1)" } + ['s (1)', 'f (1)'])
        # Exponential unwinding needs 5202 iterations here; linear needs ~250.
        expect(ui.iterations).to be < 500
      end

      it 'unwinds to the package that closes a cycle when an older version avoids it' do
        # x (2) -> a -> b -> x is circular, but x (1) has no dependencies, so
        # { x (1), a (1), b (1) } is a valid resolution. The cycle is detected
        # while activating b; b's own requirement was introduced by the
        # user-requested a, so only the requirements along the cycle (here
        # x (2)'s dependency on a) lead back to x.
        index = TestIndex.new(
          'x' => [
            TestSpecification.new('name' => 'x', 'version' => '1'),
            TestSpecification.new('name' => 'x', 'version' => '2', 'dependencies' => { 'a' => '>= 1' }),
          ],
          'a' => [
            TestSpecification.new('name' => 'a', 'version' => '1', 'dependencies' => { 'b' => '>= 1' }),
          ],
          'b' => [
            TestSpecification.new('name' => 'b', 'version' => '1', 'dependencies' => { 'x' => '>= 1' }),
          ]
        )
        # Keep declaration order: x is activated (at 2) before a and b.
        def index.sort_dependencies(dependencies, _activated, _conflicts)
          dependencies
        end
        demands = [Gem::Dependency.new('x'), Gem::Dependency.new('a')]

        resolved = described_class.new(index, TestUI.new).resolve(demands, DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s)).to match_array(['x (1)', 'a (1)', 'b (1)'])
      end

      it 'still retries an older version of the package whose activation closes a cycle' do
        # p4 -> p5 -> p2 (2) -> p4 is circular, and the cycle is detected while
        # activating p2 (2); p2 (1) has no dependencies. The requirements along
        # the cycle are for other names and must not stop p2 (1) from being
        # considered as an alternative for p2.
        index = TestIndex.new(
          'p2' => [
            TestSpecification.new('name' => 'p2', 'version' => '1'),
            TestSpecification.new('name' => 'p2', 'version' => '2', 'dependencies' => { 'p4' => '<= 1' }),
          ],
          'p4' => [
            TestSpecification.new('name' => 'p4', 'version' => '4', 'dependencies' => { 'p5' => '>= 4' }),
          ],
          'p5' => [
            TestSpecification.new('name' => 'p5', 'version' => '4', 'dependencies' => { 'p2' => '< 4' }),
          ]
        )

        resolved = described_class.new(index, TestUI.new).resolve([Gem::Dependency.new('p4')], DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s)).to match_array(['p2 (1)', 'p4 (4)', 'p5 (4)'])
      end

      it 'unwinds a long cycle without cubic requirement comparisons' do
        # p1 (2) -> p2 -> ... -> p64 -> p1 is circular; p1 (1) has no
        # dependencies. Every requirement along the cycle is binding, so there
        # are ~n requirement trees of length up to n. Looking up their states
        # by scanning the stack, and deduplicating unwind details by value
        # (hashing their requirement trees), used to make this O(n^3).
        operations = 0
        counting_dependency = Class.new(Gem::Dependency) do
          define_method(:==) do |other|
            operations += 1
            super(other)
          end

          define_method(:hash) do
            operations += 1
            super()
          end
        end
        n = 64
        spec = lambda do |name, version, deps = {}|
          TestSpecification.new('name' => name, 'version' => version, 'dependencies' => deps).tap do |s|
            s.dependencies = s.dependencies.map { |d| counting_dependency.new(d.name, d.requirement) }
          end
        end
        specs = Hash.new([])
        specs['p1'] = [spec.call('p1', '1'), spec.call('p1', '2', 'p2' => '>= 1')]
        (2..n).each { |i| specs["p#{i}"] = [spec.call("p#{i}", '1', "p#{i == n ? 1 : i + 1}" => '>= 1')] }
        index = TestIndex.new(specs)
        def index.sort_dependencies(dependencies, _activated, _conflicts)
          dependencies
        end

        resolved = described_class.new(index, TestUI.new).resolve([counting_dependency.new('p1')], DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s)).to eq(['p1 (1)'])
        # O(n^3) needs ~240_000 operations here; O(n^2) needs ~13_000.
        expect(operations).to be < 10 * n * n
      end

      it 'traces equal requirements from different parents separately when unwinding a cycle' do
        # p2 (1) and p3 (2) both require `p4 (>= 2)`, and p4 (2) -> p3 closes
        # the cycle p3 -> p4 -> p3; p3 (1) has no dependencies, so
        # { p2 (1), p3 (1), p4 (2) } is a valid resolution. With a value-based
        # `eql?` (as Bundler gives Gem::Dependency), p3's `p4 (>= 2)` used to be
        # merged with p2's, so the cycle was never traced back to p3.
        value_eql_dependency = Class.new(Gem::Dependency) do
          def eql?(other)
            self == other
          end
        end
        spec = lambda do |name, version, deps = {}|
          TestSpecification.new('name' => name, 'version' => version, 'dependencies' => deps).tap do |s|
            s.dependencies = s.dependencies.map { |d| value_eql_dependency.new(d.name, d.requirement) }
          end
        end
        index = TestIndex.new(
          'p2' => [spec.call('p2', '1', 'p4' => '>= 2')],
          'p3' => [spec.call('p3', '1'), spec.call('p3', '2', 'p4' => '>= 2')],
          'p4' => [spec.call('p4', '2', 'p3' => '!= 3')]
        )
        def index.sort_dependencies(dependencies, _activated, _conflicts)
          dependencies
        end
        demands = [value_eql_dependency.new('p2'), value_eql_dependency.new('p3')]

        resolved = described_class.new(index, TestUI.new).resolve(demands, DependencyGraph.new)

        expect(resolved.map(&:payload).map(&:to_s)).to match_array(['p2 (1)', 'p3 (1)', 'p4 (2)'])
      end

      context 'can resolve when two resolutions are equally valid' do
        INDICES.each do |index_class|
          it "with #{index_class.name.split('::').last}" do
            index = index_class.new(
              'a' => [
                TestSpecification.new('name' => 'a', 'version' => '1', 'dependencies' => { 'c' => '2', 'd' => '1' }),
                TestSpecification.new('name' => 'a', 'version' => '2', 'dependencies' => { 'c' => '1', 'd' => '2' }),
              ],
              'b' => [
                TestSpecification.new('name' => 'b', 'version' => '1', 'dependencies' => { 'c' => '1', 'd' => '2' }),
                TestSpecification.new('name' => 'b', 'version' => '2', 'dependencies' => { 'c' => '2', 'd' => '1' }),
              ],
              'c' => [
                TestSpecification.new('name' => 'c', 'version' => '1'),
                TestSpecification.new('name' => 'c', 'version' => '2'),
              ],
              'd' => [
                TestSpecification.new('name' => 'd', 'version' => '1'),
                TestSpecification.new('name' => 'd', 'version' => '2'),
              ]
            )

            requirements = [
              Gem::Dependency.new('a'),
              Gem::Dependency.new('b')
            ]

            @resolver = described_class.new(index, TestUI.new)
            resolved = @resolver.resolve(requirements, DependencyGraph.new)

            expect(resolved.map(&:payload).map(&:to_s).sort).
              to eq(['a (2)', 'b (1)', 'c (1)', 'd (2)']).
              or eq(['a (1)', 'b (2)', 'c (2)', 'd (1)'])
          end
        end
      end
    end
  end
end
