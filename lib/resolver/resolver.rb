require 'resolver/dependency_graph'

module Resolver
  class Resolver
    require 'resolver/resolution'

    attr_reader :specification_provider, :resolver_ui

    def initialize(specification_provider, resolver_ui)
      @specification_provider = specification_provider
      @resolver_ui = resolver_ui
    end

    def resolve(requested, base)
      Resolution.new(specification_provider,
                     resolver_ui,
                     requested,
                     base).
        resolve
    end
  end
end
