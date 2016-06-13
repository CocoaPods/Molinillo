# frozen_string_literal: true
require 'spec_helper'

describe Molinillo::DependencyGraph::Log do
  shared_examples_for 'replay' do |steps|
    it 'replays the log' do
      copy = Molinillo::DependencyGraph.new
      graph = Molinillo::DependencyGraph.new.tap { |g| steps.each { |s| s.call(g) } }
      graph.log.each { |a| a.up(copy) }
      expect(copy).to eq(graph)
    end

    it 'can undo to an empty graph' do
      graph = Molinillo::DependencyGraph.new
      graph.tag(self)
      steps.each { |s| s.call(graph) }
      graph.log.rewind_to(graph, self)
      expect(graph).to eq(Molinillo::DependencyGraph.new)
    end
  end

  it_behaves_like 'replay', []
  it_behaves_like 'replay', [
    proc { |g| g.add_child_vertex('Foo', 1, [nil], 4) },
    proc { |g| g.add_child_vertex('Bar', 2, ['Foo', nil], 3) },
    proc { |g| g.add_child_vertex('Baz', 3, %w(Foo Bar), 2) },
    proc { |g| g.add_child_vertex('Foo', 4, [], 1) },
  ]
end
