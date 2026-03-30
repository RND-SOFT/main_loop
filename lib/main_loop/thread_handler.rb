require 'main_loop/handler'

module MainLoop
  class ThreadHandler < MainLoop::Handler

    attr_reader :thread

    def initialize(dispatcher, name, runnable: nil, **kwargs, &block)
      super
      @handler_type = 'Thread'
      @thread = nil
      dispatcher.add_handler(self)

      if runnable
        unless runnable.respond_to?(:run) && runnable.respond_to?(:on_term)
          raise TypeError, "Runnable object must respond to :run and :on_term"
        end
      end

      @runnable = runnable
      @block = block

      run
    end

    def id
      @thread&.object_id.to_s
    end

    def reap(status)
      logger.info "Thread[#{name}] exited: thread:#{@thread} Status:#{status}"
      @thread = nil
      @finished = true

      return if terminating?
      @success = false

      handle_retry
    end

    def term
      unless @thread
        @terminating_at ||= Time.now
        logger.debug "Thread[#{name}] alredy terminated. Skipped."
        return
      end

      if terminating?
        @success = false
        logger.info "Thread[#{name}] send force terminate: KILL thread:#{@thread}"
        @thread.kill rescue nil
      else
        @terminating_at ||= Time.now
        @success = true
        logger.info "Thread[#{name}] send terminate: thread:#{@thread}"

        @runnable&.on_term(@thread) rescue nil
        @on_term&.call(@thread) rescue nil
      end
    end

    def kill
      unless @thread
        logger.debug "Thread[#{name}] alredy Killed. Skipped."
        return
      end

      @success = false
      logger.info "Thread[#{name}] send kill: thread:#{@thread}"
      @thread.kill rescue nil
    end

    def run
      return if terminating?

      if @runnable
        start_thread { @runnable.run(self) }
      elsif @block
        start_thread(&@block)
      end
    end

    protected

      def start_thread
        @thread = Thread.new do
          yield(self)
        rescue StandardError => e
          logger.error "Thread[#{name}] crashed: #{e.message}"
        ensure
          publish("reap:#{id}:exited")
        end
        @finished = false
        logger.info "Thread[#{name}] created: thread:#{@thread}"
      end


  end
end
