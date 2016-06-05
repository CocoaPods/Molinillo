require 'molinillo/dependency_graph/action'
module Molinillo
  class DependencyGraph
    # @!visibility private
    class DetachVertexNamed < Action # :nodoc:
      # @!group Action

      def self.name
        :add_vertex
      end

      def up(graph)
        return unless @vertex = graph.vertices.delete(name)
        @vertex.outgoing_edges.each do |e|
          v = e.destination
          v.incoming_edges.delete(e)
          graph.detach_vertex_named(v.name) unless v.root? || v.predecessors.any?
        end
        @vertex.incoming_edges.each do |e|
          v = e.origin
          v.outgoing_edges.delete(e)
        end
      end

      def down(graph)
        return unless @vertex
        graph.vertices[@vertex.name] = @vertex
        @vertex.outgoing_edges.each do |e|
          e.destination.incoming_edges << e
        end
        @vertex.incoming_edges.each do |e|
          e.origin.outgoing_edges << e
        end
      end

      # @!group DetachVertexNamed

      attr_reader :name

      def initialize(name)
        @name = name
      end
    end
  end
end
