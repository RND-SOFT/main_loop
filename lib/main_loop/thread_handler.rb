require 'main_loop/handler'

# = MainLoop::ThreadHandler
#
# Управляет потоками через Thread.new.
#
# == Особенности потоков
#
# - Потоки не имеют status завершения (как процессы)
# - Если завершение graceful term, то @success отражает, завершился ли он после вызова on_term (true) или после нашего kill
# - Внутри on_term поток может быть завершен так, как считает нужным разработчик метода, например
#     @stopped = true
#     @thread&.wakeup
#     @thread&.kill unless @thread&.join(2)
# - Если поток завершился сам, то смотрим на Thread.current[:exit_reason]
# - Завершение потока публикуется в ensure блоке и обрабатывается в MainLoop#start_loop_forever
#
# == Сигналы для потока
#
# При {#term}:
# - Если не терминация: вызовы @runnable.on_term / @on_term
# - Если терминация: @thread.kill (FORCE)
#
# == Пример использования
#
#   MainLoop::ThreadHandler.new dispatcher, 'worker', retry_count: 0, logger: logger do |thread|
#     loop do
#       sleep 1
#     end
#   end
#
# == См. также
# - {MainLoop::Handler} — базовый класс
# - {MainLoop::ProcessHandler} — обработчики процессов

module MainLoop
  class ThreadHandler < MainLoop::Handler
    attr_reader :thread

    # == Инициализация
    #
    # @param dispatcher [Dispatcher] ссылка на диспетчер
    # @param name [String] имя обработчика
    # @param runnable [Object] объект с методами run и on_term (опционально)
    # @param retry_count [Integer, :unlimited] количество повторов
    # @param logger [Logger] логгер
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

    # == Получить ID потока
    #
    # @return [String] object_id потока в виде строки
    def id
      @thread&.object_id.to_s
    end

    # == Обработка завершения потока
    #
    # @param status [String] статус завершения (описание)
    def reap(status)
      logger.info "Thread[#{name}] exited: thread:#{@thread} Status:#{status}"
      exit_reason = @thread[:exit_reason] if @thread
      @thread = nil
      @finished = true

      return if terminating?

      @success = (exit_reason == :normal)
      handle_retry
    end

    # == Терминация потока
    #
    # @param *_args (Unused)
    def term(*_args)
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

    # == Принудительно завершить поток
    #
    # @param *_args (Unused)
    def kill(*_args)
      unless @thread
        logger.debug "Thread[#{name}] alredy Killed. Skipped."
        return
      end

      @success = false
      logger.info "Thread[#{name}] send kill: thread:#{@thread}"
      @thread.kill rescue nil
    end

    # == Запустить поток
    #
    # Вызывает {#start_thread} с блоком или runnable.
    def run
      return if terminating?

      if @runnable
        start_thread { @runnable.run(self) }
      elsif @block
        start_thread(&@block)
      end
    end

    # == Create-thread блок (protected)
    #
    # Создает новый поток и настраивает обработку ошибок и завершения.
    #
    # @yield выполнить блок кода в потоке
    # @return [Thread] созданный поток
    protected

      def start_thread
        @thread = Thread.new do
          yield(self)
          Thread.current[:exit_reason] = :normal
        rescue StandardError => e
          Thread.current[:exit_reason] = :exception
          logger.error "Thread[#{name}] crashed: #{e.message}"
        ensure
          Thread.current[:exit_reason] ||= :killed
          publish("reap:#{id}:exited")
        end
        @finished = false
        logger.info "Thread[#{name}] created: thread:#{@thread}"
      end
  end
end
