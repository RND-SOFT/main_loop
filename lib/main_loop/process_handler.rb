require 'main_loop/handler'

module MainLoop
  class ProcessHandler < MainLoop::Handler

    attr_reader :pid

    def initialize(dispatcher, name, runnable: nil, **kwargs, &block)
      super
      @handler_type = 'Process'
      @pid = nil
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
      @pid
    end

    def reap(status)
      if status
        logger.info "Process[#{name}] exited: Pid:#{@pid} Status: #{status.exitstatus.inspect} Termsig: #{status.termsig.inspect} Success: #{status.success?}"
        @success = !!status.success?
      else 
        logger.info "Process[#{name}] exited: Pid:#{@pid} with unknown status"
        @success = true # TODO или false?
      end
      @pid = nil
      @finished = true

      return if terminating?

      handle_retry
    end

    def term
      unless @pid
        @terminating_at ||= Time.now
        logger.debug "Process[#{name}] alredy terminated. Skipped."
        return
      end

      if terminating?
        @success = false
        logger.info "Process[#{name}] send force terminate: KILL Pid:#{@pid}"
        ::Process.kill('KILL', @pid) rescue nil
      else
        @terminating_at ||= Time.now
        logger.info "Process[#{name}] send terminate: Pid:#{@pid}"

        @runnable&.on_term(@pid) rescue nil
        @on_term&.call(@pid) rescue nil

        ::Process.kill('TERM', @pid) rescue nil
      end
    end

    def kill
      unless @pid
        logger.debug "Process[#{name}] alredy Killed. Skipped."
        return
      end

      @success = false
      logger.info "Process[#{name}] send kill: Pid:#{@pid}"
      ::Process.kill('KILL', @pid) rescue nil
    end

    def run
      return if terminating?

      if @runnable
        start_fork { @runnable.run }
      elsif @block
        start_fork(&@block)
      end
    end

    protected

      def start_fork
        @pid = Kernel.fork do
          yield
        rescue StandardError => e
          logger.error "Process[#{name}] crashed: #{e.message}"
          exit!(1)
        end
        @finished = false
        logger.info "Process[#{name}] created: Pid:#{@pid}"
      end


  end
end
