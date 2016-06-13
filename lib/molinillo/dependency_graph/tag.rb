# frozen_string_literal: true
require 'molinillo/dependency_graph/action'
module Molinillo
  class DependencyGraph
    # @!visibility private
    # @see DependencyGraph#tag
    class Tag < Action
      # @!group Action

      # (see Action.name)
      def self.name
        :tag
      end

      # (see Action#up)
      def up(_graph)
      end

      # (see Action#down)
      def down(_graph)
      end

      # @!group Tag

      # @return [Object] An opaque tag
      attr_reader :tag

      # Initialize an action to tag a state of a dependency graph
      # @param [Object] tag an opaque tag
      def initialize(tag)
        @tag = tag
      end
    end
  end
end