# frozen_string_literal: true

require 'tsort'

require_relative 'dependency_graph/log'
require_relative 'dependency_graph/vertex'

module Molinillo
  # A directed acyclic graph that is tuned to hold named dependencies
  class DependencyGraph
    include Enumerable

    # Enumerates through the vertices of the graph.
    # @return [Array<Vertex>] The graph's vertices.
    def each
      return vertices.values.each unless block_given?
      vertices.values.each { |v| yield v }
    end

    include TSort

    # @!visibility private
    alias tsort_each_node each

    # @!visibility private
    def tsort_each_child(vertex, &block)
      vertex.successors.each(&block)
    end

    # Topologically sorts the given vertices.
    # @param [Enumerable<Vertex>] vertices the vertices to be sorted, which must
    #   all belong to the same graph.
    # @return [Array<Vertex>] The sorted vertices.
    def self.tsort(vertices)
      TSort.tsort(
        lambda { |&b| vertices.each(&b) },
        lambda { |v, &b| (v.successors & vertices).each(&b) }
      )
    end

    # A directed edge of a {DependencyGraph}
    # @attr [Vertex] origin The origin of the directed edge
    # @attr [Vertex] destination The destination of the directed edge
    # @attr [Object] requirement The requirement the directed edge represents
    Edge = Struct.new(:origin, :destination, :requirement)

    # @return [{String => Vertex}] the vertices of the dependency graph, keyed
    #   by {Vertex#name}
    attr_reader :vertices

    # @return [Log] the op log for this graph
    attr_reader :log

    # Initializes an empty dependency graph
    def initialize
      @vertices = {}
      @log = Log.new
    end

    # Tags the current state of the dependency as the given tag
    # @param  [Object] tag an opaque tag for the current state of the graph
    # @return [Void]
    def tag(tag)
      log.tag(self, tag)
    end

    # Rewinds the graph to the state tagged as `tag`
    # @param  [Object] tag the tag to rewind to
    # @return [Void]
    def rewind_to(tag)
      log.rewind_to(self, tag)
    end

    # Initializes a copy of a {DependencyGraph}, ensuring that all {#vertices}
    # are properly copied.
    #
    # The copy starts with an empty {#log}: it has the same vertices and edges
    # as `other`, but none of its history, so it cannot be rewound to tags
    # that were added to `other` before the copy was made. The two graphs share
    # no vertices, edges or log actions.
    # @param [DependencyGraph] other the graph to copy.
    def initialize_copy(other)
      super
      @vertices = {}
      @log = Log.new
      other.vertices.each do |name, vertex|
        new_vertex = Vertex.new(name, vertex.payload)
        new_vertex.root = vertex.root
        new_vertex.explicit_requirements.replace(vertex.explicit_requirements)
        @vertices[name] = new_vertex
      end
      other.vertices.each_value do |vertex|
        vertex.outgoing_edges.each do |edge|
          new_edge = Edge.new(@vertices[edge.origin.name], @vertices[edge.destination.name], edge.requirement)
          new_edge.origin.outgoing_edges << new_edge
          new_edge.destination.incoming_edges << new_edge
        end
      end
    end

    # @return [String] a string suitable for debugging
    def inspect
      "#{self.class}:#{vertices.values.inspect}"
    end

    # @param [Hash] options options for dot output.
    # @return [String] Returns a dot format representation of the graph
    def to_dot(options = {})
      edge_label = options.delete(:edge_label)
      raise ArgumentError, "Unknown options: #{options.keys}" unless options.empty?

      dot_vertices = []
      dot_edges = []
      vertices.each do |n, v|
        dot_vertices << "  #{n} [label=\"{#{n}|#{v.payload}}\"]"
        v.outgoing_edges.each do |e|
          label = edge_label ? edge_label.call(e) : e.requirement
          dot_edges << "  #{e.origin.name} -> #{e.destination.name} [label=#{label.to_s.dump}]"
        end
      end

      dot_vertices.uniq!
      dot_vertices.sort!
      dot_edges.uniq!
      dot_edges.sort!

      dot = dot_vertices.unshift('digraph G {').push('') + dot_edges.push('}')
      dot.join("\n")
    end

    # @param [DependencyGraph] other
    # @return [Boolean] whether the two dependency graphs are equal, determined
    #   by a recursive traversal of each {#root_vertices} and its
    #   {Vertex#successors}
    def ==(other)
      return false unless other
      return true if equal?(other)
      return false unless vertices.size == other.vertices.size
      vertices.all? do |name, vertex|
        other_vertex = other.vertex_named(name)
        other_vertex &&
          vertex.payload == other_vertex.payload &&
          other_vertex.successors.to_set == vertex.successors.to_set
      end
    end

    # Adds a vertex with the given name (see {#add_vertex}) and an edge to it
    # from each of the named parents. A `nil` parent name marks `requirement`
    # as an explicit requirement of a root vertex.
    #
    # This is not atomic: if it raises, the changes made before the error
    # remain in the graph. To recover, {#tag} the graph beforehand and
    # {#rewind_to} that tag.
    # @param [String] name
    # @param [Object] payload
    # @param [Array<String>] parent_names
    # @param [Object] requirement the requirement that is requiring the child
    # @raise [CircularDependencyError] see {#add_edge}
    # @return [Vertex] the vertex that was added to `self`
    def add_child_vertex(name, payload, parent_names, requirement)
      root = !parent_names.delete(nil) { true }
      vertex = add_vertex(name, payload, root)
      log.add_explicit_requirement(self, name, requirement) if root
      parent_names.each do |parent_name|
        parent_vertex = vertex_named(parent_name)
        add_edge(parent_vertex, vertex, requirement)
      end
      vertex
    end

    # Adds a vertex with the given name, or updates the existing one.
    # @param [String] name
    # @param [Object] payload
    # @return [Vertex] the vertex that was added to `self`
    def add_vertex(name, payload, root = false)
      log.add_vertex(self, name, payload, root)
    end

    # Detaches the {#vertex_named} `name` {Vertex} from the graph, recursively
    # removing any non-root vertices that were orphaned in the process
    # @param [String] name
    # @return [Array<Vertex>] the vertices which have been detached
    def detach_vertex_named(name)
      log.detach_vertex_named(self, name)
    end

    # @param [String] name
    # @return [Vertex,nil] the vertex with the given name
    def vertex_named(name)
      vertices[name]
    end

    # @param [String] name
    # @return [Vertex,nil] the root vertex with the given name
    def root_vertex_named(name)
      vertex = vertex_named(name)
      vertex if vertex && vertex.root?
    end

    # Adds a new {Edge} to the dependency graph
    # @param [Vertex] origin
    # @param [Vertex] destination
    # @param [Object] requirement the requirement that this edge represents
    # @raise [CircularDependencyError] if the edge would create a cycle. Building
    #   the error calls `possibilities` on the payload of each vertex on the
    #   cycle, so cycle detection requires resolver payloads (which respond to
    #   `possibilities`); other payloads, including `nil`, raise `NoMethodError`.
    # @return [Edge] the added edge
    def add_edge(origin, destination, requirement)
      if destination.path_to?(origin)
        raise CircularDependencyError.new(path(destination, origin))
      end
      add_edge_no_circular(origin, destination, requirement)
    end

    # Deletes an {Edge} from the dependency graph
    # @param [Edge] edge
    # @return [Void]
    def delete_edge(edge)
      log.delete_edge(self, edge.origin.name, edge.destination.name, edge.requirement)
    end

    # Sets the payload of the vertex with the given name
    # @param [String] name the name of the vertex
    # @param [Object] payload the payload
    # @return [Void]
    def set_payload(name, payload)
      log.set_payload(self, name, payload)
    end

    private

    # Adds a new {Edge} to the dependency graph without checking for
    # circularity.
    # @param (see #add_edge)
    # @return (see #add_edge)
    def add_edge_no_circular(origin, destination, requirement)
      log.add_edge_no_circular(self, origin.name, destination.name, requirement)
    end

    # Returns the path between two vertices
    # @raise [ArgumentError] if there is no path between the vertices
    # @param [Vertex] from
    # @param [Vertex] to
    # @return [Array<Vertex>] the shortest path from `from` to `to`
    def path(from, to)
      # Breadth-first search from `from`, so the first time a vertex is reached
      # is along a shortest path, independent of vertex insertion order.
      predecessors = { from.name => nil }
      queue = [from]
      until queue.empty? || predecessors.key?(to.name)
        vertex = queue.shift
        vertex.successors.each do |successor|
          next if predecessors.key?(successor.name)
          predecessors[successor.name] = vertex
          queue << successor
        end
      end

      unless predecessors.key?(to.name)
        raise ArgumentError, "There is no path from #{from.name} to #{to.name}"
      end

      path = [to]
      while before = predecessors[path.last.name]
        path << before
      end
      path.reverse
    end
  end
end
