module Resolver
  module Specification
    def name
      inspect
    end

    def version_compare(other)
      self <=> other
    end
  end
end
