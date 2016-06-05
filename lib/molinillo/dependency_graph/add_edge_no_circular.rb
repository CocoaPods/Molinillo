require 'molinillo/dependency_graph/action'
module Molinillo
  class DependencyGraph
    # @!visibility private
    class AddEdgeNoCircular < Action # :nodoc:
      # @!group Action

      def self.name
        :add_vertex
      end

      def up(graph)
        edge = make_edge(graph)
        edge.origin.outgoing_edges << edge
        edge.destination.incoming_edges << edge
        edge
      end

      def down(graph)
        edge = make_edge(graph)
        edge.origin.outgoing_edges.delete(edge)
        edge.destination.incoming_edges.delete(edge)
      end

      # @!group AddEdgeNoCircular

      attr_reader :origin
      attr_reader :destination
      attr_reader :requirement

      def make_edge(graph)
        Edge.new(graph.vertex_named(origin), graph.vertex_named(destination), requirement)
      end

      def initialize(origin, destination, requirement)
        @origin = origin
        @destination = destination
        @requirement = requirement
      end
    end
  end
end
