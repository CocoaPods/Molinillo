# frozen_string_literal: true

require File.expand_path('../spec_helper', __FILE__)

module Molinillo
  describe VersionConflict do
    let(:earliest) { Gem::Dependency.new('s', '>= 2') }
    let(:redundant) { Gem::Dependency.new('s', '= 2') }
    let(:trigger) { Gem::Dependency.new('s', '= 1') }
    let(:trees) do
      [[Gem::Dependency.new('a1'), earliest], [Gem::Dependency.new('a2'), redundant],
       [Gem::Dependency.new('f'), trigger]]
    end
    let(:specs) do
      [1, 2, 3].map { |v| TestSpecification.new('name' => 's', 'version' => v.to_s) }
    end
    let(:provider) { TestIndex.new('s' => specs) }
    let(:graph) do
      DependencyGraph.new.tap do |g|
        vertex = g.add_vertex('s', nil, true)
        vertex.explicit_requirements.concat([earliest, redundant, trigger])
      end
    end
    let(:conflict) do
      Resolver::Resolution::Conflict.new(trigger, { 'user-specified dependency' => [earliest, redundant, trigger] },
                                         nil, nil, nil, trees, {}, nil)
    end

    def explanation
      described_class.new({ 's' => conflict }, provider, graph)
    end

    it 'omits a redundant parent from the resolver error without changing the conflict requirements' do
      index = TestIndex.new(
        'a1' => [1, 2, 3].map do |v|
          TestSpecification.new('name' => 'a1', 'version' => v.to_s, 'dependencies' => { 's' => "= #{v}" })
        end,
        'a2' => [1, 2, 3].map do |v|
          TestSpecification.new('name' => 'a2', 'version' => v.to_s, 'dependencies' => { 's' => '>= 2' })
        end,
        'f' => [TestSpecification.new('name' => 'f', 'version' => '1', 'dependencies' => { 's' => '= 1' })],
        's' => specs
      )
      def index.sort_dependencies(dependencies, _activated, _conflicts)
        dependencies
      end
      requested = [Gem::Dependency.new('a1', '>= 2'), Gem::Dependency.new('a2'), Gem::Dependency.new('f')]
      expect { Resolver.new(index, TestUI.new).resolve(requested) }.to raise_error(VersionConflict) do |error|
        expect(error.message_with_trees).to include('a1', 'f', 's')
        expect(error.message_with_trees).not_to include('a2')
        expect(error.conflicts['s'].requirements.size).to eq(error.original_conflicts['s'].requirements.size)
      end
    end

    it 'prunes redundant trees, keeping the earliest blocker and triggering requirement' do
      expect(explanation.conflicts['s'].requirement_trees).to eq([trees.first, trees.last])
      expect(explanation.message_with_trees).not_to include('a2')
      expect(explanation.message).not_to include('s (= 2)')
    end

    it 'preserves original conflicts and never mutates the requirements used for unwinding' do
      error = explanation
      expect(error.original_conflicts['s']).to equal(conflict)
      expect(conflict.requirement_trees).to equal(trees)
      expect(error.conflicts['s'].requirements).to equal(conflict.requirements)
      expect(graph.vertex_named('s').explicit_requirements).to eq([earliest, redundant, trigger])
    end

    it 'distinguishes value-equal requirements from different parents by identity' do
      other = Gem::Dependency.new('s', '>= 2')
      conflict.requirements['user-specified dependency'][1] = other
      trees[1][1] = other
      graph.vertex_named('s').explicit_requirements[1] = other
      expect(explanation.conflicts['s'].requirement_trees).to eq([trees.first, trees.last])
    end

    it 'keeps the triggering occurrence even when an earlier requirement is value-equal' do
      other = Gem::Dependency.new('s', '= 1')
      conflict.requirements['user-specified dependency'][1] = other
      trees[1][1] = other
      graph.vertex_named('s').explicit_requirements[1] = other
      expect(explanation.conflicts['s'].requirement_trees).to eq([trees.first, trees.last])
    end

    it 'prefers an explicit root over a redundant transitive requirement' do
      trees[1] = [redundant]
      expect(explanation.conflicts['s'].requirement_trees).to eq([trees[1], trees.last])
    end

    it 'does not prune cached conflicts using the final conflict graph' do
      error = described_class.new({ 's' => conflict }, provider, graph, 'another-name')
      expect(error.conflicts['s'].requirement_trees).to eq(trees)
    end

    it 'retains circular conflicts unchanged' do
      conflict.underlying_error = ResolverError.new('cycle')
      expect(explanation.conflicts['s'].requirement_trees).to eq(trees)
    end

    it 'retains conflicts without a conflict-time graph' do
      expect(described_class.new({ 's' => conflict }, provider).conflicts['s'].requirement_trees).to eq(trees)
    end

    it 'retains stale conflicts when the graph no longer contains their requirements' do
      graph.vertex_named('s').explicit_requirements.clear
      expect(explanation.conflicts['s'].requirement_trees).to eq(trees)
    end

    it 'retains everything when the full requirements do not prove unsatisfiability' do
      conflict.requirement = earliest
      trees.last[1] = earliest
      conflict.requirements['user-specified dependency'][2] = earliest
      graph.vertex_named('s').explicit_requirements[2] = earliest
      expect(explanation.conflicts['s'].requirement_trees).to eq(trees)
    end

    it 'keeps locks as background constraints and still displays the snapshot' do
      lock = specs.first
      conflict.locked_requirement = lock
      conflict.requirements['Lockfile'] = [lock]
      conflict.requirement = earliest
      expect(explanation.conflicts['s'].requirement_trees).to eq([trees.first])
      expect(explanation.message_with_trees).to include('In snapshot', 's (1)')
    end

    it 'falls back to the original trees if a provider cannot evaluate the reporting context' do
      allow(provider).to receive(:requirement_satisfied_by?).and_raise(ArgumentError, 'context unavailable')
      expect(explanation.conflicts['s'].requirement_trees).to eq(trees)
    end

    it 'skips pruning if deleting a requirement changes context-sensitive satisfaction' do
      allow(provider).to receive(:requirement_satisfied_by?) do |req, activated, spec|
        req.requirement.satisfied_by?(spec.version) &&
          activated.vertex_named('s').requirements.any? { |r| r.equal?(redundant) }
      end
      expect(explanation.conflicts['s'].requirement_trees).to eq(trees)
    end
  end

  describe NoSuchDependencyError do
    let(:dependency) { Gem::Dependency.new('foo', '>= 1.0') }
    let(:required_by) { [] }

    subject { described_class.new(dependency, required_by) }

    describe '#message' do
      it 'says it is unable to find the spec' do
        expect(subject.message).to eq('Unable to find a specification for `foo (>= 1.0)`')
      end

      context 'when #required_by is not empty' do
        let(:required_by) { %w(spec-1 spec-2) }

        it 'includes the source names' do
          expect(subject.message).to eq(
            'Unable to find a specification for `foo (>= 1.0)` depended upon by `spec-1` and `spec-2`'
          )
        end
      end
    end
  end
end
