require 'logger'

module MainLoop
  class Handler

    attr_reader :dispatcher, :name, :logger

    def initialize(dispatcher, name, *_args, retry_count: 0, logger: nil, **_kwargs)
      @dispatcher = dispatcher
      @name = name
      @code = 0
      @retry_count = retry_count
      @logger = logger || Logger.new(nil)
      @handler_type = 'Unknown'
    end

    # :nocov:
    def id(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # :nocov:
    def term(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # :nocov:
    def run(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # :nocov:
    def kill(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # :nocov:
    def reap(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # :nocov:
    def publish(event)
      dispatcher.bus.puts(event)
    end
    # :nocov:

    def on_term &block
      @on_term = block
    end

    # :nocov:
    def finished?
      @finished
    end
    # :nocov:

    # :nocov:
    def success?
      finished? && @success
    end
    # :nocov:

    # :nocov:
    def running?
      !finished?
    end
    # :nocov:

    # :nocov:
    def terminating?
      @terminating_at
    end
    # :nocov:

    def handle_retry
      if @retry_count == :unlimited
        logger.info "#{@handler_type}[#{name}] retry...."
        self.run(&@block)
      elsif @retry_count && (@retry_count -= 1) >= 0
        logger.info "#{@handler_type}[#{name}] retry...."
        self.run(&@block)
      else
        publish(:term)
      end
    end

  end
end

