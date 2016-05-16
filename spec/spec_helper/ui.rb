module Molinillo
  class TestUI
    include UI

    def output
      @output ||= if debug?
        $stderr
      else
        File.open('/dev/null', 'w')
      end
    end
  end
end
