require 'molinillo/dependency_graph/action'
module Molinillo
  class DependencyGraph
    class Tag < Action
      # @!group Action

      def self.name
        :tag
      end

      def up(_graph)
      end

      def down(_graph)
      end

      # @!group Tag

      attr_reader :tag

      def initialize(tag)
        @tag = tag
      end
    end
  end
end
