module Resolver
  class DependencyGraph
    Edge = Struct.new(:origin, :destination)

    attr_reader :root_vertices, :vertices, :edges

    class CircularDependencyError < StandardError
      attr_reader :dependencies

      def initialize(*dependencies)
        @dependencies = dependencies
        super "There is a circular dependency between #{dependencies * ' and '}"
      end
    end

    #
    # Create a new Directed Acyclic Graph
    #
    # @param [Hash] options configuration options
    #
    def initialize
      require 'set'
      @vertices = {}
      @edges = Set.new
      @root_vertices = {}
    end

    def inspect
      "DependencyGraph:#{vertices.inspect}"
    end

    def ==(other)
      root_vertices == other.root_vertices
    end

    def add_vertex(name, payload)
      Vertex.new(self, name, payload).tap { |v| vertices[name] = v }
    end

    def add_root_vertex(name, payload)
      add_vertex(name, payload).tap { |v| root_vertices[name] = v }
    end

    def vertex_named(name)
      vertices[name]
    end

    def add_edge(origin, destination)
      raise ArgumentError, 'Origin must be a vertex in this dependency graph' unless
        origin && origin.graph == self
      raise ArgumentError, 'Destination must be a vertex in this dependency graph' unless
       destination && destination.graph == self
      if origin == destination || destination.path_to?(origin)
        raise CircularDependencyError.new(origin.payload, destination.payload)
      end
      Edge.new(origin, destination).tap { |e| edges << e }
    end

    class Vertex
      attr_reader :graph, :name, :payload

      def initialize(graph, name, payload)
        @graph = graph
        @name = name
        @payload = payload
      end

      def outgoing_edges
        graph.edges.select { |e| e.origin.shallow_eql?(self) }
      end

      def incoming_edges
        graph.edges.select { |e| e.destination..shallow_eql?(self) }
      end

      def predecessors
        incoming_edges.map(&:origin).uniq
      end

      def successors
        outgoing_edges.map(&:destination).uniq
      end

      def inspect
        "DependencyGraph::Vertex:#{name}(#{payload.inspect})"
      end

      def ==(other)
        shallow_eql?(other) &&
          successors == other.successors
      end

      def shallow_eql?(other)
        name == other.name &&
          payload == other.payload
      end

      alias_method :eql?, :==

      def hash
        name.hash
      end

      #
      # Is there a path from here to +other+ following edges in the DAG?
      #
      # @param [DAG::Vertex] another Vertex is the same DAG
      # @raise [ArgumentError] if +other+ is not a Vertex in the same DAG
      # @return true iff there is a path following edges within this DAG
      #
      def path_to?(other)
        successors.include?(other) || successors.any? { |v| v.path_to?(other) }
      end

      alias_method :descendent?, :path_to?

      #
      # Is there a path from +other+ to here following edges in the DAG?
      #
      # @param [DAG::Vertex] another Vertex is the same DAG
      # @raise [ArgumentError] if +other+ is not a Vertex in the same DAG
      # @return true iff there is a path following edges within this DAG
      #
      def ancestor?(other)
        predecessors.include?(other) || predecessors.any? { |v| v.ancestor?(other) }
      end

      alias_method :is_reachable_from?, :ancestor?
    end
  end
end
