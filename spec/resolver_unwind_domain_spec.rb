# frozen_string_literal: true

require 'spec_helper'

describe 'pure unwind search-domain membership' do
  let(:requirement) { Gem::Dependency.new('a', '>= 0') }
  let(:provider) { double('provider') }
  let(:resolution) do
    Molinillo::Resolver::Resolution.new(provider, Molinillo::TestUI.new, [], Molinillo::DependencyGraph.new)
  end
  let(:spec_class) do
    Class.new do
      attr_reader :value, :comparisons
      def initialize(value)
        @value = value
        @comparisons = 0
      end

      def ==(other)
        @comparisons += 1
        value == other.value
      end

      def eql?(_other)
        raise 'eql? must not be used'
      end

      def hash
        raise 'hash must not be used'
      end
    end
  end

  def includes?(candidate)
    resolution.send(:unwind_search_domain_includes?, requirement, candidate)
  end

  it 'finds identical candidates without walking preceding value comparisons' do
    candidates = Array.new(100) { |i| spec_class.new(i) }
    expect(provider).to receive(:search_for).with(requirement).once.and_return(candidates)
    5.times { expect(includes?(candidates.last)).to eq(true) }
    expect(candidates.map(&:comparisons).inject(0, :+)).to eq(0)
  end

  it 'preserves == matches even when eql?/hash are incompatible or undefined' do
    original = spec_class.new(1)
    equivalent = spec_class.new(1)
    expect(provider).to receive(:search_for).with(requirement).once.and_return([original])
    5.times { expect(includes?(equivalent)).to eq(true) }
    expect(original.comparisons).to eq(1)
  end

  it 'memoizes negative scans as well as positive matches' do
    candidates = Array.new(100) { |i| spec_class.new(i) }
    missing = spec_class.new(101)
    expect(provider).to receive(:search_for).with(requirement).once.and_return(candidates)
    5.times { expect(includes?(missing)).to eq(false) }
    expect(candidates.map(&:comparisons).inject(0, :+)).to eq(100)
  end

  it 'keeps equal requirement objects from different parents separate' do
    other = Gem::Dependency.new('a', '>= 0')
    candidate = spec_class.new(1)
    expect(provider).to receive(:search_for).twice.and_return([candidate])
    expect(includes?(candidate)).to eq(true)
    expect(resolution.send(:unwind_search_domain_includes?, other, candidate)).to eq(true)
  end

  it 'does not cache failed searches' do
    expect(provider).to receive(:search_for).twice.and_raise(Molinillo::NoSuchDependencyError.new(requirement))
    2.times { expect { includes?(spec_class.new(1)) }.to raise_error(Molinillo::NoSuchDependencyError) }
  end
end
