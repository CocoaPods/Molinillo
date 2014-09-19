module Resolver
  class ResolverError < StandardError
    attr_reader :dependencies
    def initialize(message, *dependencies)
      require 'set'
      @dependencies = Set.new(dependencies)
      super message
    end
  end

  class CircularDependencyError < ResolverError
    def initialize(*nodes)
      super "There is a circular dependency between #{nodes.map(&:name) * ' and '}",
        *nodes.map(&:payload)
    end
  end

  class VersionConflict < ResolverError
    def initialize(*dependencies)
      super "There is a version conflict between #{dependencies.to_s * ' and '}",
        *dependencies
    end
  end
end
