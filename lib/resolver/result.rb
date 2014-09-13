module Resolver
  class Resolver
    class Result
      attr_reader :conflicts, :dependency_graph

      def initialize(dependency_graph, conflicts)
        @dependency_graph = dependency_graph
        @conflicts = conflicts
      end

      def ==(other)
        conflicts == other.conflicts &&
          dependency_graph == other.dependency_graph
      end
    end
  end
end
