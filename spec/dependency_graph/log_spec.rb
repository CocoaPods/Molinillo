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

  it 'undoes explicit requirements added by add_child_vertex' do
    graph = Molinillo::DependencyGraph.new
    graph.add_child_vertex('a', 'a', [nil], 'first')
    graph.tag(:before)
    graph.add_child_vertex('a', 'a', [nil], 'second')
    expect(graph.vertex_named('a').explicit_requirements).to eq(%w(first second))
    graph.rewind_to(:before)
    expect(graph.vertex_named('a').explicit_requirements).to eq(%w(first))
    expect(graph.vertex_named('a').requirements).to eq(%w(first))
  end

  it 'only enumerates the actions that have not been undone' do
    graph = Molinillo::DependencyGraph.new
    graph.add_vertex('a', 'a', true)
    graph.tag(:before)
    graph.add_vertex('b', 'b', true)
    graph.rewind_to(:before)
    expect(graph.log.each.map { |a| a.class.action_name }).to eq([:add_vertex])
    expect(graph.log.each.to_a).to eq(graph.log.reverse_each.to_a.reverse)
  end

  describe 'undoing delete_edge' do
    def edges(graph)
      graph.flat_map { |v| v.outgoing_edges.map { |e| [e.origin.name, e.destination.name, e.requirement] } }
    end

    let(:graph) do
      Molinillo::DependencyGraph.new.tap do |g|
        g.add_vertex('a', 'a', true)
        g.add_vertex('b', 'b', true)
      end
    end

    it 'deletes and restores exactly one of several equal edges' do
      2.times { graph.add_edge(graph.vertex_named('a'), graph.vertex_named('b'), 'req') }
      graph.tag(:before_delete)
      graph.delete_edge(graph.vertex_named('a').outgoing_edges.first)
      expect(edges(graph)).to eq([%w(a b req)])
      expect(graph.vertex_named('b').incoming_edges.size).to eq(1)
      graph.rewind_to(:before_delete)
      expect(edges(graph)).to eq([%w(a b req), %w(a b req)])
      expect(graph.vertex_named('b').incoming_edges.size).to eq(2)
    end

    it 'does not create an edge that was never there' do
      graph.tag(:before_delete)
      edge = Molinillo::DependencyGraph::Edge.new(graph.vertex_named('a'), graph.vertex_named('b'), 'req')
      graph.delete_edge(edge)
      graph.rewind_to(:before_delete)
      expect(edges(graph)).to be_empty
      expect(graph.vertex_named('b').incoming_edges).to be_empty
    end
  end

  describe 'actions that raise' do
    let(:graph) { Molinillo::DependencyGraph.new.tap { |g| g.add_vertex('a', 'a', true) } }

    it 'does not record an action whose application raised' do
      graph.tag(:before)
      expect { graph.set_payload('missing', 'payload') }.to raise_error(NoMethodError)
      expect(graph.log.reverse_each.first).to be_a(Molinillo::DependencyGraph::Tag)
      expect { graph.rewind_to(:before) }.not_to raise_error
      expect(graph.vertices.keys).to eq(%w(a))
    end

    it 'still records actions in order when one action records others' do
      graph.add_child_vertex('b', 'b', %w(a), 'b')
      graph.tag(:before)
      graph.detach_vertex_named('a')
      graph.rewind_to(:before)
      expect(graph.vertex_named('a').outgoing_edges.map { |e| e.destination.name }).to eq(%w(b))
      expect(graph.vertex_named('b').incoming_edges.map { |e| e.origin.name }).to eq(%w(a))
    end
  end

  it 'raises without undoing anything when rewinding to an unknown tag' do
    graph = Molinillo::DependencyGraph.new
    graph.add_vertex('a', 'a', true)
    graph.tag(:known)
    graph.add_child_vertex('b', 'b', %w(a), 'b')
    expect { graph.rewind_to(:unknown) }.to raise_error(RuntimeError, 'No tag :unknown found')
    expect(graph.vertices.keys).to eq(%w(a b))
    expect(graph.vertex_named('a').successors.map(&:name)).to eq(%w(b))
    graph.rewind_to(:known)
    expect(graph.vertices.keys).to eq(%w(a))
  end

  it_behaves_like 'replay', []
  it_behaves_like 'replay', [
    proc { |g| g.add_child_vertex('Foo', 1, [nil], 4) },
    proc { |g| g.add_child_vertex('Bar', 2, ['Foo', nil], 3) },
    proc { |g| g.add_child_vertex('Baz', 3, %w(Foo Bar), 2) },
    proc { |g| g.add_child_vertex('Foo', 4, [], 1) },
  ]
end
