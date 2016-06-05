require 'molinillo/dependency_graph/action'
module Molinillo
  class DependencyGraph
    # @!visibility private
    class SetPayload < Action # :nodoc:
      # @!group Action

      def self.name
        :set_payload
      end

      def up(graph)
        vertex = graph.vertex_named(name)
        @old_payload = vertex.payload
        vertex.payload = payload
      end

      def down(graph)
        graph.vertex_named(name).payload = @old_payload
      end

      # @!group SetPayload

      attr_reader :name
      attr_reader :payload

      def initialize(name, payload)
        @name = name
        @payload = payload
      end
    end
  end
end
