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
