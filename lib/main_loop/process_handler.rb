require 'main_loop/handler'

# = MainLoop::ProcessHandler
#
# Управляет субпроцессами через Kernel.fork.
#
# == Жизненный цикл процесса
#
# 1. {#run} вызывает {#start_fork}
# 2. {#start_fork} создает fork с обработкой ошибок
# 3. process выполняется и завершается
# 4. {#reap(status)} получает статус завершения
# 5. {#handle_retry} решает, повторить или отправить term
#
# == Сигналы для процесса
#
# При {#term}:
# - Если не терминация: Process.kill('TERM', pid) + вызовы @runnable.on_term / @on_term
# - Если терминация: Process.kill('KILL', pid)
#
# == Пример использования
#
#   MainLoop::ProcessHandler.new dispatcher, 'worker', retry_count: 3, logger: logger do
#     sleep 2
#     exit! 0
#   end
#
# == См. также
# - {MainLoop::Handler} — базовый класс
# - {MainLoop::ThreadHandler} — обработчики потоков

module MainLoop
  class ProcessHandler < MainLoop::Handler
    attr_reader :pid

    # == Инициализация
    #
    # @param dispatcher [Dispatcher] ссылка на диспетчер
    # @param name [String] имя обработчика
    # @param runnable [Object] объект с методами run и on_term (опционально)
    # @param retry_count [Integer, :unlimited] количество повторов
    # @param logger [Logger] логгер
    # @option runnable [Object] nil
    # @option retry_count [Integer, :unlimited] 0
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

    # == Получить PID процесса
    #
    # @return [Integer|nil] PID процесса или nil если не создан
    def id
      @pid
    end

    # == Обработка завершения процесса
    #
    # @param status [Process::Status|nil] статус завершения или nil если неизвестен
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

    # == Отправить сигнал терминации
    #
    # @param *_args (Unused)
    def term(*_args)
      unless @pid
        @terminating_at ||= Time.now
        logger.debug "Process[#{name}] already terminated. Skipped."
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

    # == Принудительно завершить процесс
    #
    # @param *_args (Unused)
    def kill(*_args)
      unless @pid
        logger.debug "Process[#{name}] already Killed. Skipped."
        return
      end

      @success = false
      logger.info "Process[#{name}] send kill: Pid:#{@pid}"
      ::Process.kill('KILL', @pid) rescue nil
    end

    # == Запустить процесс
    #
    # Вызывает {#start_fork} с блоком или runnable.
    def run
      return if terminating?

      if @runnable
        start_fork { @runnable.run }
      elsif @block
        start_fork(&@block)
      end
    end

    # == Fork-блок (protected)
    #
    # Создает дочерний процесс и настраивает обработку ошибок.
    #
    # @yield выполнить блок кода в дочернем процессе
    # @return [Integer] PID дочернего процесса
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
