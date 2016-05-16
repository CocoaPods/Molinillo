require 'molinillo/dependency_graph/action'

module Molinillo
  class DependencyGraph
    class Log
      def self.action(name__, parameters = nil, &blk)
        name__ = name__.to_sym
        cls = Class.new(Action) do
          define_singleton_method(:name) { name__ }
          if parameters || (method = begin
                                       DependencyGraph.instance_method(name__)
                                     rescue
                                       nil
                                     end)
            parameters ||= method.parameters.map(&:last)
            module_eval <<-EOS
              #{parameters.map { |param| "attr_reader(:#{param});" }.join}
              define_method(:initialize) do |#{parameters.join(', ')}|
                #{parameters.map { |p| "@#{p} = #{p};" }.join}
                @args = [#{parameters.join(', ')}]
              end
            EOS
          end
          module_exec(&blk)
        end

        define_method(name__) do |graph, *args|
          action = cls.new(*args)
          @actions << action
          action.up(graph)
        end
      end

      def initialize
        @actions = []
      end

      action(:tag, %w(tag)) do
        def down(graph); end

        def up(graph); end
      end

      action(:add_vertex) do
        def up(graph)
          existing = graph.vertices[name]
          @existing = existing && [existing.payload, existing.root]
          vertex = graph.vertices[name] ||= Vertex.new(name, payload)
          vertex.payload ||= payload
          vertex.root ||= root
          vertex
        end

        def down(graph)
          if @existing
            vertex = graph.vertices[name]
            vertex.payload, vertex.root = @existing
          else
            graph.vertices.delete(name)
          end
        end
      end

      action(:detach_vertex_named) do
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
          graph.vertices[name] = @vertex
          @vertex.outgoing_edges.each do |e|
            e.destination.incoming_edges << e
          end
          @vertex.incoming_edges.each do |e|
            e.origin.outgoing_edges << e
          end
        end
      end

      action(:add_edge) do
        def up(_graph)
          edge = make_edge
          origin.outgoing_edges << edge
          destination.incoming_edges << edge
          edge
        end

        def down(_graph)
          edge = make_edge
          origin.outgoing_edges.delete(edge)
          destination.incoming_edges.delete(edge)
        end

        def make_edge
          Edge.new(origin, destination, requirement)
        end
      end

      action(:set_payload) do
        def up(graph)
          vertex = graph.vertex_named(name)
          @old_payload = vertex.payload
          vertex.payload = payload
        end

        def down(graph)
          graph.vertex_named(name).payload = @old_payload
        end
      end

      def pop!(graph)
        @actions.pop.tap do |action|
          action.down(graph) if action
        end
      end

      def rewind_to(graph, tag)
        loop do
          action = pop!(graph)
          raise "No tag #{tag.inspect} found" unless action
          break if action.class.name == :tag && action.tag == tag
        end
      end
    end
  end
end
