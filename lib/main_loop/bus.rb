require 'monitor'
require 'timeouter'

module MainLoop
  class Bus

    include MonitorMixin

    attr_reader :read, :write

    EOL = "\n".freeze

    def initialize
      super()
      @read, @write = IO.pipe
      @read.sync = true
      @write.sync = true
      @buffer = ''
    end

    def empty?(timeout = 0)
      !wait_for_event(timeout)
    end

    def close
      @write.close rescue nil
      @read.close rescue nil
    end

    def closed?
      @write.closed? || @read.closed?
    end

    def puts(str)
      synchronize do
        @write.puts str.to_s
      end
    end

    def wait_for_event(timeout)
      IO.select([@read], [], [], timeout)
    end

    def gets(timeout)
      Timeouter.loop(timeout) do |t|
        line = gets_nonblock if wait_for_event(t.left)
        return line if line
      end
    end

    def gets_nonblock
      while (ch = @read.read_nonblock(1))
        @buffer << ch
        next if ch != MainLoop::Bus::EOL

        line = @buffer
        @buffer = ''
        return line&.strip
      end
      nil
    rescue IO::WaitReadable
      nil
    end

  end
end

