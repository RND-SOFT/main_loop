require 'monitor'
require 'logger'

module MainLoop
  class Dispatcher

    include MonitorMixin

    attr_reader :bus, :handlers, :logger

    def initialize(bus, timeout: 5, logger: nil)
      super()
      @bus = bus
      @timeout = timeout
      @handlers = []
      @logger = logger || Logger.new(nil)
    end

    def reap(statuses)
      statuses.each do |(pid, status)|
        reap_by_id(pid, status)
      end
    end

    def reap_by_id(id, status)
      synchronize do
        if (handler = handlers.find {|h| h.id == id })
          logger.info("Reap handler #{handler.name.inspect}. Status: #{status.inspect}")
          handler.reap(status)
        else
          logger.debug("Reap unknown handler. Status: #{status.inspect}. Skipped")
        end
      end
    end

    def add_handler(handler)
      synchronize do
        handler.term if terminating?
        handlers << handler
      end
    end

    def terminating?
      @terminating_at
    end

    def term
      synchronize do
        if terminating?
          logger.info('Terminate FORCE all handlers')
          handlers.each(&:kill)
        else
          @terminating_at ||= Time.now
          logger.info('Terminate all handlers')
          handlers.each(&:term)
        end
      end
    end

    def tick
      log_status if logger.debug?
      return unless terminating?

      try_exit!

      return if @killed || !need_force_kill?

      @killed = true
      logger.info('Killing all handlers by timeout')
      handlers.each(&:kill)
    end

    def need_force_kill?
      @terminating_at && (Time.now - @terminating_at) >= @timeout
    end

    # :nocov:
    def try_exit!
      synchronize do
        return unless handlers.all?(&:finished?)

        logger.info('All handlers finished exiting...')
        status = handlers.all?(&:success?) ? 0 : 1
        exit status
      end
    end
    # :nocov:

    # :nocov:
    def log_status
      total = handlers.size
      running = handlers.count(&:running?)
      finihsed = handlers.count(&:finished?)
      term_text = terminating? ? 'TERM' : ''
      logger.debug("Total:#{total} Running:#{running} Finihsed:#{finihsed}. #{term_text}".strip)
    end
    # :nocov:

  end
end

