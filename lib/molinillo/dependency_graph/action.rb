module Molinillo
  class DependencyGraph
    class Action
      def self.name
        raise 'Abstract'
      end

      def up(_graph)
        raise 'Abstract'
      end

      def down(_graph)
        raise 'Abstract'
      end
    end
  end
end
