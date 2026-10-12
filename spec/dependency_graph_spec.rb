# frozen_string_literal: true

require File.expand_path('../spec_helper', __FILE__)

module Molinillo
  describe DependencyGraph do
    describe 'in general' do
      before do
        @graph = described_class.new
        @root  = @graph.add_vertex('Root', 'Root', true)
        @root2 = @graph.add_vertex('Root2', 'Root2', true)
        @child = @graph.add_child_vertex('Child', 'Child', %w(Root), 'Child')
      end

      it 'returns root vertices by name' do
        expect(@graph.root_vertex_named('Root')).to eq(@root)
      end

      it 'returns vertices by name' do
        expect(@graph.vertex_named('Root')).to eq(@root)
        expect(@graph.vertex_named('Child')).to eq(@child)
      end

      it 'returns nil for non-existent root vertices' do
        expect(@graph.root_vertex_named('missing')).to be_nil
      end

      it 'returns nil for non-existent vertices' do
        expect(@graph.vertex_named('missing')).to be_nil
      end
    end

    describe 'adding an edge that creates a cycle' do
      def graph_with(*names)
        described_class.new.tap do |graph|
          names.each do |name|
            payload = Resolver::Resolution::PossibilitySet.new([], [name])
            graph.add_vertex(name, payload, false)
          end
        end
      end

      def add_edges(graph, *pairs)
        pairs.each { |o, d| graph.add_edge(graph.vertex_named(o), graph.vertex_named(d), "#{o}->#{d}") }
      end

      it 'raises a circular dependency error when vertices were added out of order' do
        graph = graph_with('mid', 'top', 'leaf')
        add_edges(graph, %w(top mid), %w(mid leaf))
        expect { add_edges(graph, %w(leaf top)) }.
          to raise_error(CircularDependencyError, 'There is a circular dependency between top and mid and leaf')
      end

      it 'reports the shortest path between the circularly-dependent vertices' do
        graph = graph_with('b', 'f', 'a', 'd', 'e')
        add_edges(graph, %w(d e), %w(e f), %w(a b), %w(a d), %w(b f))
        expect { add_edges(graph, %w(f a)) }.
          to raise_error(CircularDependencyError, 'There is a circular dependency between a and b and f')
      end
    end

    describe 'topologically sorting a subset of vertices' do
      it 'orders each vertex after its successors' do
        graph = described_class.new
        a = graph.add_vertex('a', 'a', true)
        b = graph.add_child_vertex('b', 'b', %w(a), 'b')
        c = graph.add_child_vertex('c', 'c', %w(b), 'c')
        expect(described_class.tsort([a, b])).to eq([b, a])
        expect(described_class.tsort([a, b, c])).to eq([c, b, a])
      end
    end

    describe 'equality' do
      def graph_with(*names)
        described_class.new.tap { |g| names.each { |n| g.add_vertex(n, n, true) } }
      end

      it 'is not equal to a graph with additional vertices, in either direction' do
        smaller = graph_with('a')
        larger = graph_with('a', 'b')
        expect(smaller == larger).to be(false)
        expect(larger == smaller).to be(false)
      end

      it 'returns true for equal graphs' do
        expect(graph_with('a', 'b') == graph_with('b', 'a')).to be(true)
      end
    end

    describe 'detaching a vertex' do
      before do
        @graph = described_class.new
      end

      it 'detaches a root vertex without successors' do
        root = @graph.add_vertex('root', 'root', true)
        @graph.detach_vertex_named(root.name)
        expect(@graph.vertex_named(root.name)).to be_nil
        expect(@graph.vertices).to be_empty
      end

      it 'detaches a root vertex with successors' do
        root = @graph.add_vertex('root', 'root', true)
        child = @graph.add_child_vertex('child', 'child', %w(root), 'child')
        @graph.detach_vertex_named(root.name)
        expect(@graph.vertex_named(root.name)).to be_nil
        expect(@graph.vertex_named(child.name)).to be_nil
        expect(@graph.vertices).to be_empty
      end

      it 'detaches a root vertex with successors with other parents' do
        root = @graph.add_vertex('root', 'root', true)
        root2 = @graph.add_vertex('root2', 'root2', true)
        child = @graph.add_child_vertex('child', 'child', %w(root root2), 'child')
        @graph.detach_vertex_named(root.name)
        expect(@graph.vertex_named(root.name)).to be_nil
        expect(@graph.vertex_named(child.name)).to eq(child)
        expect(child.predecessors).to contain_exactly(root2)
        expect(@graph.vertices.count).to eq(2)
      end

      it 'detaches a vertex with predecessors' do
        parent = @graph.add_vertex('parent', 'parent', true)
        child = @graph.add_child_vertex('child', 'child', %w(parent), 'child')
        @graph.detach_vertex_named(child.name)
        expect(@graph.vertex_named(child.name)).to be_nil
        expect(@graph.vertices).to eq(parent.name => parent)
        expect(parent.outgoing_edges).to be_empty
      end
    end
  end
end
