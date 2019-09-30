require 'logger'
require 'timeouter'

module MainLoop

  TERM_SIGNALS = %w[INT TERM].freeze

  class Loop

    attr_reader :logger

    def initialize(bus, dispatcher, logger: nil)
      STDOUT.sync = true
      STDERR.sync = true
      @bus = bus
      @dispatcher = dispatcher
      @logger = logger || Logger.new(nil)
    end

    def run(timeout = 0)
      install_signal_handlers(@bus)

      start_loop_forever(timeout)
    rescue StandardError => e
      # :nocov:
      logger.fatal("Exception in Main Loop: #{e.inspect}")
      exit!(2)
      # :nocov:
    end

    def start_loop_forever(timeout = 0)
      wait = [[(timeout / 2.5), 5].min, 5].max
      Timeouter.loop(timeout) do
        event = @bus.gets(wait)
        logger.debug("command:#{event}")

        case event
        when 'term'
          term(event)
        when 'crash'
          crash(event)
        when /sig:/
          signal(event)
        when /reap:/
          reap(event)
        when nil
          logger.debug('Empty event: reaping...')
        else
          logger.debug("unknown event:#{event}")
        end

        @dispatcher.reap(reap_children) rescue nil
        @dispatcher.tick
      end
    end

    # :nocov:
    def install_signal_handlers(bus)
      TERM_SIGNALS.each do |sig|
        trap(sig) do |*_args|
          Thread.new(bus) {|b| b.puts "sig:#{sig}" }
        end
      end

      trap 'CLD' do
        Thread.new(bus) {|b| b.puts 'sig:CLD' }
      end
    end
    # :nocov:

    def signal(command)
      _, sig = command.split(':')
      logger.debug("signal:#{sig}")

      if TERM_SIGNALS.include?(sig)
        @dispatcher.term
      elsif sig == 'CLD'
        # nothing to do child will reap later
      else
        logger.info("unhandled signal:#{sig}")
      end
    end

    def term(_command)
      @dispatcher.term unless @dispatcher.terminating?
    end

    def crash(_command)
      @dispatcher.crash
    end

    def reap(command)
      _, id, status = command.split(':')
      @dispatcher.reap_by_id(id, status)
    end

    def reap_children
      results = []

      @dispatcher.pids.each do |pid|
        if (result = self.wait2(pid))
          results << result
        end
      end

      Timeouter.loop(2) do
        unless (result = self.wait2(-1))
          break
        end

        results << result
      end

      results
    rescue Errno::ECHILD
      results
    end

    # :nocov:
    def wait2(pid)
      Process.wait2(pid, ::Process::WNOHANG)
    end
    # :nocov:

  end

end

