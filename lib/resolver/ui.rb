module Resolver
  module UI
    def indicate_progress
      STDOUT.print '.'
    end

    def debug
      if ENV['DEBUG_RESOLVER']
        debug_info = yield
        debug_info = debug_info.inspect unless debug_info.is_a?(String)
        STDERR.puts debug_info
      end
    end
  end
end
