# frozen_string_literal: true

require_relative 'action'
module Molinillo
  class DependencyGraph
    # @!visibility private
    # @see DependencyGraph#add_child_vertex
    class AddExplicitRequirement < Action # :nodoc:
      # @!group Action

      # (see Action.action_name)
      def self.action_name
        :add_explicit_requirement
      end

      # (see Action#up)
      def up(graph)
        graph.vertex_named(name).explicit_requirements << requirement
      end

      # (see Action#down)
      def down(graph)
        requirements = graph.vertex_named(name).explicit_requirements
        index = requirements.rindex { |r| r.equal?(requirement) }
        requirements.delete_at(index) if index
      end

      # @!group AddExplicitRequirement

      # @return [String] the name of the vertex
      attr_reader :name

      # @return [Object] the explicit requirement being added
      attr_reader :requirement

      # Initialize an action to add an explicit requirement to a vertex in a
      # dependency graph
      # @param [String] name the name of the vertex
      # @param [Object] requirement the explicit requirement
      def initialize(name, requirement)
        @name = name
        @requirement = requirement
      end
    end
  end
end
