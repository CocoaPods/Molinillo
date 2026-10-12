# frozen_string_literal: true

require 'spec_helper'

describe 'context requirement augmentation' do
  let(:resolution) do
    Molinillo::Resolver::Resolution.new(
      Object.new.extend(Molinillo::SpecificationProvider), Molinillo::TestUI.new, [], Molinillo::DependencyGraph.new
    )
  end
  let(:vertex) { Molinillo::DependencyGraph::Vertex.new('a', nil) }
  let(:other_vertex) { Molinillo::DependencyGraph::Vertex.new('parent', nil) }

  def missing(requirements)
    resolution.send(:missing_context_requirements, vertex, requirements)
  end

  it 'does not build/hash the full requirement set when exact objects are already present' do
    existing = Array.new(50) { |i| Gem::Dependency.new('a', ">= #{i}") }
    vertex.explicit_requirements.concat(existing)
    expect(vertex).not_to receive(:requirements)
    existing.each { |r| expect(r).not_to receive(:hash) }
    expect(missing([existing.first, existing.last])).to eq([])
  end

  it 'recognizes identity matches on incoming edges without deduplication' do
    requirement = Gem::Dependency.new('a')
    vertex.incoming_edges << Molinillo::DependencyGraph::Edge.new(other_vertex, vertex, requirement)
    expect(vertex).not_to receive(:requirements)
    expect(missing([requirement])).to eq([])
  end

  it 'preserves value-based eql?/hash subtraction for equal non-identical requirements' do
    klass = Class.new(Gem::Dependency) do
      def eql?(other)
        self == other
      end
    end
    existing = klass.new('a', '>= 1')
    equivalent = klass.new('a', '>= 1')
    vertex.explicit_requirements.concat([existing, existing])
    expect(missing([equivalent])).to eq([equivalent] - vertex.requirements)
    expect(missing([equivalent])).to eq([])
  end

  it 'keeps distinct value-equal identity-eql requirements as augmentation when required' do
    existing = Gem::Dependency.new('a', '>= 1')
    distinct = Gem::Dependency.new('a', '>= 1')
    vertex.explicit_requirements << existing
    expect(missing([distinct])).to eq([distinct] - vertex.requirements)
  end

  it 'keeps duplicates and order on the left side exactly as Array subtraction does' do
    present = Gem::Dependency.new('a', '>= 1')
    absent = Gem::Dependency.new('a', '< 3')
    vertex.explicit_requirements.concat([present, present])
    wanted = [absent, absent, present]
    expect(missing(wanted)).to eq(wanted - vertex.requirements)
    expect(vertex.explicit_requirements).to eq([present, present])
  end
end
