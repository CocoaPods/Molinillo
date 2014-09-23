module Resolver
  # A directed acyclic graph that is tuned to hold named dependencies
  class DependencyGraph
    # A directed edge of a {DependencyGraph}
    # @attr [Vertex] origin The origin of the directed edge
    # @attr [Vertex] destination The destination of the directed edge
    Edge = Struct.new(:origin, :destination)

    # @return [{String => Vertex}] vertices that have no {Vertex#predecessors},
    #   keyed by by {Vertex#name}
    attr_reader :root_vertices
    # @return [{String => Vertex}] the vertices of the dependency graph, keyed
    #   by {Vertex#name}
    attr_reader :vertices
    # @return [Set<Edge>] the edges of the dependency graph
    attr_reader :edges

    def initialize
      require 'set'
      @vertices = {}
      @edges = Set.new
      @root_vertices = {}
    end

    # Initializes a copy of a {DependencyGraph}, ensuring that all {#vertices}
    # have the correct {Vertex#graph} set
    def initialize_copy(other)
      super
      @vertices = other.vertices.reduce({}) do |vertices, (name, vertex)|
        vertices.tap do |hash|
          hash[name] = vertex.dup.tap { |v| v.graph = self }
        end
      end
      @root_vertices = Hash[vertices.select { |n, _v| other.root_vertices[n] }]
      @edges = other.edges.map do |edge|
        Edge.new vertex_named(edge.origin.name), vertex_named(edge.destination.name)
      end
    end

    # @return [String] a string suitable for debugging
    def inspect
      "DependencyGraph:#{vertices.values.inspect}"
    end

    # @return [Boolean] whether the two dependency graphs are equal, determined
    #   by a recursive traversal of each {#root_vertices} and its
    #   {Vertex#successors}
    def ==(other)
      root_vertices == other.root_vertices
    end

    # @param [String] name
    # @param [Object] payload
    # @param [Array<String>] parent_names
    # @return [void]
    def add_child_vertex(name, payload, parent_names)
      is_root = parent_names.include?(nil)
      parent_nodes = parent_names.compact.map { |n| vertex_named(n) }
      vertex = vertex_named(name) || if is_root
                                       add_root_vertex(name, payload)
                                     else
                                       add_vertex(name, payload)
                                     end
      vertex.payload ||= payload
      parent_nodes.each do |parent_node|
        add_edge(parent_node, vertex)
      end
      vertex
    end

    # @param [String] name
    # @param [Object] payload
    # @return [Vertex] the vertex that was added to `self`
    def add_vertex(name, payload)
      Vertex.new(self, name, payload).tap { |v| vertices[name] = v }
    end

    # @param [String] name
    # @param [Object] payload
    # @return [Vertex] the vertex that was added to `self`
    def add_root_vertex(name, payload)
      add_vertex(name, payload).tap { |v| root_vertices[name] = v }
    end

    # @param [String] name
    # @return [Vertex,nil] the vertex with the given name
    def vertex_named(name)
      vertices[name]
    end

    # @param [String] name
    # @return [Vertex,nil] the root vertex with the given name
    def root_vertex_named(name)
      root_vertices[name]
    end

    # Adds a new {Edge} to the dependency graph
    # @param [Vertex] origin
    # @param [Vertex] destination
    # @return [Edge] the added edge
    def add_edge(origin, destination)
      if origin == destination || destination.path_to?(origin)
        raise CircularDependencyError.new([origin, destination])
      end
      Edge.new(origin, destination).tap { |e| edges << e }
    end

    # A vertex in a {DependencyGraph} that encapsulates a {#name} and a
    # {#payload}
    class Vertex
      # @return [DependencyGraph] the graph this vertex is a node of
      attr_accessor :graph

      # @return [String] the name of the vertex
      attr_accessor :name

      # @return [Object] payload the payload the vertex holds
      attr_accessor :payload

      # @param [DependencyGraph] graph see {#graph}
      # @param [String] name see {#name}
      # @param [Object] payload see {#payload}
      def initialize(graph, name, payload)
        @graph = graph
        @name = name
        @payload = payload
      end

      # @return [Array<Edge>] the edges of {#graph} that have `self` as their
      #   {Edge#origin}
      def outgoing_edges
        graph.edges.select { |e| e.origin.shallow_eql?(self) }
      end

      # @return [Array<Edge>] the edges of {#graph} that have `self` as their
      #   {Edge#destination}
      def incoming_edges
        graph.edges.select { |e| e.destination.shallow_eql?(self) }
      end

      # @return [Set<Vertex>] the vertices of {#graph} that have an edge with
      #   `self` as their {Edge#destination}
      def predecessors
        incoming_edges.map(&:origin).to_set
      end

      # @return [Set<Vertex>] the vertices of {#graph} that have an edge with
      #   `self` as their {Edge#origin}
      def successors
        outgoing_edges.map(&:destination).to_set
      end

      # @return [String] a string suitable for debugging
      def inspect
        "DependencyGraph::Vertex:#{name}(#{payload.inspect})"
      end

      # @return [Boolean] whether the two vertices are equal, determined
      #   by a recursive traversal of each {Vertex#successors}
      def ==(other)
        shallow_eql?(other) &&
          successors == other.successors
      end

      # @return [Boolean] whether the two vertices are equal, determined
      #   solely by {#name} and {#payload} equality
      def shallow_eql?(other)
        other &&
          name == other.name &&
          payload == other.payload
      end

      alias_method :eql?, :==

      # @return [Fixnum] a hash for the vertex based upon its {#name}
      def hash
        name.hash
      end

      # Is there a path from `self` to `other` following edges in the
      # dependency graph?
      # @return true iff there is a path following edges within this {#graph}
      def path_to?(other)
        successors.include?(other) || successors.any? { |v| v.path_to?(other) }
      end

      alias_method :descendent?, :path_to?

      # Is there a path from `other` to `self` following edges in the
      # dependency graph?
      # @return true iff there is a path following edges within this {#graph}
      def ancestor?(other)
        predecessors.include?(other) || predecessors.any? { |v| v.ancestor?(other) }
      end

      alias_method :is_reachable_from?, :ancestor?
    end
  end
end
