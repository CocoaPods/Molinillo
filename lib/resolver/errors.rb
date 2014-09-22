module Resolver
  # An error that occurred during the resolution process that holds the
  # {#dependencies} that caused the error
  class ResolverError < StandardError
    # [Set<Object>] the dependencies responsible for causing the error
    attr_reader :dependencies

    # @param [Array<Object>] dependencies see {#dependencies}
    # @param [String] message an informative message that explains why the error
    #   is being `raise`d
    def initialize(message, *dependencies)
      require 'set'
      @dependencies = Set.new(dependencies)
      super message
    end
  end

  # An error caused by attempting to fulfil a dependency that was circular
  #
  # @note This exception will be thrown iff a {Vertex} is added to a
  #   {DependencyGraph} that has a {DependencyGraph::Vertex#path_to?} an
  #   existing {DependencyGraph::Vertex}
  class CircularDependencyError < ResolverError
    # @param [Array<DependencyGraph::Vertex>] nodes the nodes in the dependency
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
