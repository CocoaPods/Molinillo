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

      attr_accessor :previous, :next
    end
  end
end
