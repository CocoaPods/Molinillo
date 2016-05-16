require 'spec_helper'

describe Molinillo::DependencyGraph::Log do
  shared_examples_for "replay" do |steps|
    it "replays the log" do
      copy = Molinillo::DependencyGraph.new
      graph = Molinillo::DependencyGraph.new.tap {|g| steps.each {|s| s.call(g) }}
      graph.log.instance_variable_get(:@actions).each {|a| a.up(copy) }
      expect(copy).to eq(graph)
    end

    it "can undo to an empty graph" do
      graph =  Molinillo::DependencyGraph.new.tap {|g| steps.each {|s| s.call(g) }}
      while graph.log.pop!(graph); end
      expect(graph).to eq(Molinillo::DependencyGraph.new)
    end
  end

  it_behaves_like "replay", []
  it_behaves_like "replay", [
    ->(g)  { g.add_child_vertex('Foo', 1, [nil], 4) },
    ->(g)  { g.add_child_vertex('Bar', 2, ['Foo', nil], 3) },
    ->(g)  { g.add_child_vertex('Baz', 3, %w(Foo Bar), 2) },
    ->(g)  { g.add_child_vertex('Foo', 4, [], 1) },
  ]
end
