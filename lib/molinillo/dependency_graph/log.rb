require 'molinillo/dependency_graph/add_edge_no_circular'
require 'molinillo/dependency_graph/add_vertex'
require 'molinillo/dependency_graph/detach_vertex_named'
require 'molinillo/dependency_graph/set_payload'
require 'molinillo/dependency_graph/tag'

module Molinillo
  class DependencyGraph
    class Log
      def initialize
        @current_action = @first_action = nil
      end

      def push_action(graph, action)
        action.previous = @current_action
        @current_action.next = action if @current_action
        @current_action = action
        @first_action ||= action
        action.up(graph)
      end

      def tag(graph, tag)
        push_action(graph, Tag.new(tag))
      end

      def add_vertex(graph, name, payload, root)
        push_action(graph, AddVertex.new(name, payload, root))
      end

      def detach_vertex_named(graph, name)
        push_action(graph, DetachVertexNamed.new(name))
      end

      def add_edge_no_circular(graph, origin, destination, requirement)
        push_action(graph, AddEdgeNoCircular.new(origin, destination, requirement))
      end

      def set_payload(graph, name, payload)
        push_action(graph, SetPayload.new(name, payload))
      end

      def pop!(graph)
        return unless action = @current_action
        unless @current_action = action.previous
          @first_action = nil
        end
        action.down(graph)
        action
      end

      extend Enumerable

      def each
        action = @first_action
        loop do
          break unless action
          yield action
          action = action.next
        end
        self
      end

      def reverse_each
        action = @current_action
        loop do
          break unless action
          yield action
          action = action.previous
        end
        self
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
