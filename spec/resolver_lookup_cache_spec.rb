# frozen_string_literal: true

require 'spec_helper'

describe Molinillo::Resolver::Resolution do
  let(:spec) { Molinillo::TestSpecification.new('name' => 'a', 'version' => '1') }
  let(:provider) { Molinillo::TestIndex.new('a' => [spec]) }
  let(:dependency) { Gem::Dependency.new('a', '>= 0') }
  let(:resolution) { described_class.new(provider, Molinillo::TestUI.new, [], Molinillo::DependencyGraph.new) }

  it 'reuses a pure search without sharing mutable result arrays' do
    expect(provider).to receive(:search_for).with(dependency).once.and_call_original
    first = resolution.search_for(dependency)
    first.clear
    expect(resolution.search_for(dependency)).to eq([spec])
    expect(provider.specs['a']).to eq([spec])
  end

  it 'caches empty search answers too' do
    missing = Gem::Dependency.new('a', '> 9')
    expect(provider).to receive(:search_for).with(missing).once.and_call_original
    expect(resolution.search_for(missing)).to eq([])
    expect(resolution.search_for(missing)).to eq([])
  end

  it 'does not merge equal requirements from distinct parents in its cache' do
    other = Gem::Dependency.new('a', '>= 0')
    expect(provider).to receive(:search_for).twice.and_call_original
    2.times do
      expect(resolution.search_for(dependency)).to eq([spec])
      expect(resolution.search_for(other)).to eq([spec])
    end
  end

  it 'does not carry cached searches into another resolution' do
    expect(provider).to receive(:search_for).twice.and_call_original
    resolution.search_for(dependency)
    second = described_class.new(provider, Molinillo::TestUI.new, [], Molinillo::DependencyGraph.new)
    second.search_for(dependency)
  end

  it 'does not cache exceptions or change their class and message' do
    expect(provider).to receive(:search_for).with(dependency).twice.
      and_raise(Molinillo::NoSuchDependencyError.new(dependency))
    2.times do
      expect { resolution.search_for(dependency) }.to raise_error(Molinillo::NoSuchDependencyError, /Unable to find/)
    end
  end

  it 'memoizes names using input identity and keeps delegated methods public' do
    expect(provider).to receive(:name_for).with(dependency).once.and_call_original
    expect(resolution.name_for(dependency)).to eq('a')
    expect(resolution.name_for(dependency)).to eq('a')
    expect(resolution.public_methods).to include(:search_for, :name_for)
  end
end
