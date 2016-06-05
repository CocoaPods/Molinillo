require 'molinillo/dependency_graph/action'
module Molinillo
  class DependencyGraph
    # @!visibility private
    class AddVertex < Action # :nodoc:
      # @!group Action

      def self.name
        :add_vertex
      end

      def up(graph)
        if existing = graph.vertices[name]
          @existing_payload = existing.payload
          @existing_root = existing.root
        end
        vertex = existing || Vertex.new(name, payload)
        graph.vertices[vertex.name] = vertex
        vertex.payload ||= payload
        vertex.root ||= root
        vertex
      end

      def down(graph)
        if defined?(@existing_payload)
          vertex = graph.vertices[name]
          vertex.payload = @existing_payload
          vertex.root = @existing_root
        else
          graph.vertices.delete(name)
        end
      end

      # @!group AddVertex

      attr_reader :name
      attr_reader :payload
      attr_reader :root

      def initialize(name, payload, root)
        @name = name
        @payload = payload
        @root = root
      end
    end
  end
end
