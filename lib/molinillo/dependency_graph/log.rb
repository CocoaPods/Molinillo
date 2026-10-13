# frozen_string_literal: true

require_relative 'add_edge_no_circular'
require_relative 'add_explicit_requirement'
require_relative 'add_vertex'
require_relative 'delete_edge'
require_relative 'detach_vertex_named'
require_relative 'set_payload'
require_relative 'tag'

module Molinillo
  class DependencyGraph
    # A log for dependency graph actions
    class Log
      # Initializes an empty log
      def initialize
        @current_action = @first_action = nil
      end

      # @!macro [new] action
      #   {include:DependencyGraph#$0}
      #   @param [Graph] graph the graph to perform the action on
      #   @param (see DependencyGraph#$0)
      #   @return (see DependencyGraph#$0)

      # @macro action
      def tag(graph, tag)
        push_action(graph, Tag.new(tag))
      end

      # @macro action
      def add_vertex(graph, name, payload, root)
        push_action(graph, AddVertex.new(name, payload, root))
      end

      # @macro action
      def detach_vertex_named(graph, name)
        push_action(graph, DetachVertexNamed.new(name))
      end

      # @macro action
      def add_edge_no_circular(graph, origin, destination, requirement)
        push_action(graph, AddEdgeNoCircular.new(origin, destination, requirement))
      end

      # {include:DependencyGraph#delete_edge}
      # @param [Graph] graph the graph to perform the action on
      # @param [String] origin_name
      # @param [String] destination_name
      # @param [Object] requirement
      # @return (see DependencyGraph#delete_edge)
      def delete_edge(graph, origin_name, destination_name, requirement)
        push_action(graph, DeleteEdge.new(origin_name, destination_name, requirement))
      end

      # @macro action
      def set_payload(graph, name, payload)
        push_action(graph, SetPayload.new(name, payload))
      end

      # Adds an explicit requirement to the vertex with the given name
      # @param [DependencyGraph] graph the graph to perform the action on
      # @param [String] name the name of the vertex
      # @param [Object] requirement the explicit requirement
      # @return [Array<Object>] the vertex's explicit requirements
      def add_explicit_requirement(graph, name, requirement)
        push_action(graph, AddExplicitRequirement.new(name, requirement))
      end

      # Pops the most recent action from the log and undoes the action
      # @param [DependencyGraph] graph
      # @return [Action] the action that was popped off the log
      def pop!(graph)
        return unless action = @current_action
        if @current_action = action.previous
          @current_action.next = nil
        else
          @first_action = nil
        end
        action.down(graph)
        action
      end

      extend Enumerable

      # @!visibility private
      # Enumerates each action in the log
      # @yield [Action]
      def each
        return enum_for unless block_given?
        action = @first_action
        loop do
          break unless action
          yield action
          action = action.next
        end
        self
      end

      # @!visibility private
      # Enumerates each action in the log in reverse order
      # @yield [Action]
      def reverse_each
        return enum_for(:reverse_each) unless block_given?
        action = @current_action
        loop do
          break unless action
          yield action
          action = action.previous
        end
        self
      end

      # @macro action
      # @raise [RuntimeError] if there is no such tag, without undoing anything
      def rewind_to(graph, tag)
        unless reverse_each.any? { |action| tag?(action, tag) }
          raise "No tag #{tag.inspect} found"
        end
        loop do
          action = pop!(graph)
          break if tag?(action, tag)
        end
      end

      private

      # @return [Boolean] whether the action is a tag action for the given tag
      def tag?(action, tag)
        action.class.action_name == :tag && action.tag == tag
      end

      # Adds the given action to the log, running the action.
      #
      # The action is linked in before it runs, so that any actions it records
      # while running (e.g. recursive detaches) come after it and are undone
      # first. If running it raises, it is unlinked again, so that a failed
      # action is never undone by a later rewind.
      # @param [DependencyGraph] graph
      # @param [Action] action
      # @return The value returned by `action.up`
      def push_action(graph, action)
        action.previous = @current_action
        @current_action.next = action if @current_action
        @current_action = action
        @first_action ||= action
        begin
          action.up(graph)
        rescue StandardError
          unlink(action)
          raise
        end
      end

      # Removes the given action from the log without undoing it
      # @param [Action] action
      # @return [Void]
      def unlink(action)
        previous = action.previous
        following = action.next
        if previous
          previous.next = following
        else
          @first_action = following
        end
        if following
          following.previous = previous
        else
          @current_action = previous
        end
        action.previous = action.next = nil
      end
    end
  end
end
