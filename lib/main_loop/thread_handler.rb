require 'main_loop/handler'

module MainLoop

  class ThreadHandler < MainLoop::Handler

    attr_reader :thread

    def initialize(dispatcher, name, **kwargs, &block)
      super
      @handler_type = 'Thread'
      @thread = nil
      dispatcher.add_handler(self)

      run(&block) if block_given?
    end

    def id
      @thread&.object_id.to_s
    end

    def reap(status)
      logger.info "Thread[#{name}] exited: thread:#{@thread} Status:#{status}"
      @thread = nil
      @finished = true
      @success = false

      return if terminating?

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
        logger.info "Thread[#{name}] send terminate: thread:#{@thread}"
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

    def run(&block)
      return if terminating?

      @block = block
      start_thread(&@block)
    end

    protected

      def start_thread
        @thread = Thread.new do
          yield(self)
        ensure
          publish("reap:#{id}:exited")
        end
        @finished = false
        logger.info "Thread[#{name}] created: thread:#{@thread}"
      end


  end
end

