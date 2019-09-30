require 'main_loop/handler'

module MainLoop
  class ProcessHandler < MainLoop::Handler

    attr_reader :pid

    def initialize(dispatcher, name, **kwargs, &block)
      super
      @handler_type = 'Process'
      @pid = nil
      dispatcher.add_handler(self)

      run(&block) if block_given?
    end

    def id
      @pid
    end

    def reap(status)
      logger.info "Process[#{name}] exited: Pid:#{@pid} Status: #{status.exitstatus.inspect} Termsig: #{status.termsig.inspect} Success: #{status.success?}"
      @pid = nil
      @finished = true
      @success = !!status.success?

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

    def run(&block)
      return if terminating?

      @block = block
      start_fork(&@block)
    end

    protected

      def start_fork
        @pid = Kernel.fork do
          yield
        end
        @finished = false
        logger.info "Process[#{name}] created: Pid:#{@pid}"
      end


  end
end

