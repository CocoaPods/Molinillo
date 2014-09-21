module Resolver
  # An error that occurred during the resolution process that holds the
  # {#dependencies} that caused the error
  class ResolverError < StandardError
    # The dependencies responsible for causing the error
    attr_reader :dependencies

    # @param [Array] dependencies see {#dependencies}
    def initialize(message, *dependencies)
      require 'set'
      @dependencies = Set.new(dependencies)
      super message
    end
  end

  # An error caused by attempting to fulfil a dependency that was circular
  class CircularDependencyError < ResolverError
    # @param [DependencyGraph::Vertex] nodes the nodes in the dependency graph
    #   that caused the error
    def initialize(*nodes)
      super "There is a circular dependency between #{nodes.map(&:name) * ' and '}",
        *nodes.map(&:payload)
    end
  end

  class VersionConflict < ResolverError
    def initialize(dependencies)
      super "There is a version conflict between #{dependencies * ' and '}",
        *dependencies
    end
  end
end
