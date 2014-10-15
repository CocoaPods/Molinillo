module Molinillo
  module UI
    def indicate_progress; end

    def debug(depth = 0)
      if ENV['CP_RESOLVER']
        debug_info = yield
        debug_info = debug_info.inspect unless debug_info.is_a?(String)
        STDERR.puts debug_info.split("\n").map { |s| '  ' * depth + s }
      end
    end
  end
end
