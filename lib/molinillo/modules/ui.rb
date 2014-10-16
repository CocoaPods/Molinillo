module Molinillo
  # Conveys information about the resolution process to a user.
  module UI
    # Called roughly every second, this method should convey progress to the
    # user.
    #
    # @return [void]
    def indicate_progress; end

    # Conveys debug information to the user.
    #
    # @param [Integer] depth the current depth of the resolution process.
    # @return [void]
    def debug(depth = 0)
      if ENV['CP_RESOLVER']
        debug_info = yield
        debug_info = debug_info.inspect unless debug_info.is_a?(String)
        STDERR.puts debug_info.split("\n").map { |s| '  ' * depth + s }
      end
    end
  end
end
