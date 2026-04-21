require 'monitor'
require 'logger'

# = MainLoop::Dispatcher
#
# Координирует обработчиков, управляет жизненным циклом, обрабатывает сигнал терминации с таймаутом.
#
# Использует {MonitorMixin} для потоко-безопасности. Управляет списком обработчиков ({handlers})
# и обеспечивает корректное завершение всех обработчиков при получении сигнала терминации.
#
# == Жизненный цикл обработчиков
#
# 1. Регистрация через {add_handler}
# 2. Обработка сигнала терминации через {term}
# 3. Если не завершились за timeout → {kill}
# 4. {try_exit!} когда все завершены
#
# == Пример использования
#
#   bus = MainLoop::Bus.new
#   dispatcher = MainLoop::Dispatcher.new(bus, timeout: 10, logger: logger)
#
#   MainLoop::ProcessHandler.new dispatcher, 'worker' do
#     # код процесса
#   end
#
#   dispatcher.term  # инициировать терминацию
#
# == См. также
# - {MainLoop::Bus} — канал событий
# - {MainLoop::Handler} — базовый класс обработчиков
# - {MainLoop::Loop} — координирует Dispatcher

module MainLoop
  class Dispatcher
    include MonitorMixin

    attr_reader :bus, :handlers, :logger

    # == Инициализация
    #
    # @param bus [Bus] канал событий
    # @param timeout [Integer] таймаут для принудительного завершения в секундах (по умолчанию 5)
    # @param logger [Logger] логгер (по умолчанию Logger.new(nil))
    # @option bus [Bus]
    # @option timeout [Integer] 5
    # @option logger [Logger] nil
    def initialize(bus, timeout: 5, logger: nil)
      super()
      @bus = bus
      @timeout = timeout
      @handlers = []
      @logger = logger || Logger.new(nil)
      @exit_code = 0
    end

    # == Обработка завершения процессов
    #
    # Обрабатывает массив завершенных процессов.
    #
    # @param statuses [Array<Array>] массив пар (pid, status)
    # @example
    #   dispatcher.reap([[123, status], [456, nil]])
    def reap(statuses)
      statuses.each do |(pid, status)|
        reap_by_id(pid, status)
      end
    end

    # == Обработка завершения процесса по ID
    #
    # Находит обработчика по ID и вызывает его {Handler#reap}.
    #
    # @param id [String] идентификатор обработчика (pid для процессов, object_id для потоков)
    # @param status [Process::Status|nil] статус завершения или nil если неизвестен
    def reap_by_id(id, status)
      synchronize do
        if (handler = handlers.find {|h| h.id == id })
          logger.info("Reap handler #{handler.name.inspect}. Status: #{status&.inspect}")
          handler.reap(status)
        else
          logger.debug("Reap unknown handler. Status: #{status&.inspect}. Skipped")
        end
      end
    end

    # == Регистрация обработчика
    #
    # Добавляет обработчик в список. Если уже происходит терминация,
    # сразу посылает `term` новому обработчику.
    #
    # @param handler [Handler] обработчик для регистрации
    def add_handler(handler)
      synchronize do
        handler.term if terminating?
        handlers << handler
      end
    end

    # == Проверка терминации
    #
    # @return [Time|nil] момент начала терминации или nil если не терминация
    def terminating?
      @terminating_at
    end

    # == Инициировать терминацию
    #
    # Отправляет сигнал терминации всем обработчикам.
    # Если уже в процессе терминации — принудительное завершение (kill).
    #
    # Если это первый вызов:
    # - Устанавливает @terminating_at = Time.now
    # - Отправляет term каждому обработчику
    #
    # Если уже терминация:
    # - Отправляет kill каждому обработчику
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

    # == Отправить сигнал аварийного завершения
    #
    # Устанавливает код выхода 3 и инициирует терминацию.
    # Если уже терминация — ничего не делает.
    def crash
      @exit_code = 3
      term unless terminating?
    end

    # == Тик цикла диспетчера
    #
    # Вызывается в каждом цикле {MainLoop#start_loop_forever}.
    # Проверяет необходимость принудительного завершения по timeout.
    def tick
      log_status if logger.debug?
      return unless terminating?

      try_exit!

      return if @killed || !need_force_kill?

      @killed = true
      logger.info('Killing all handlers by timeout')
      handlers.each(&:kill)
    end

    # == Проверка необходимости принудительного завершения
    #
    # Проверяет, превышен ли timeout с момента начала терминации.
    #
    # @return [Boolean] true если timeout превышен
    def need_force_kill?
      @terminating_at && (Time.now - @terminating_at) >= @timeout
    end

    # == Получить список PID процессов
    #
    # @return [Array<Integer>] массив PID всех процессовых обработчиков
    def pids
      handlers.map{|h| h.pid rescue nil }.compact
    end

    # == Завершить программу
    #
    # Если все обработчики завершены, вызывает exit с соответствующим кодом.
    #
    # Код выхода:
    # - @exit_code если все обработчики завершились успешно
    # - 1 если любой обработчик завершился с ошибкой
    #
    # :nocov:
    def try_exit!
      synchronize do
        return unless handlers.all?(&:finished?)

        logger.info('All handlers finished exiting...')
        status = handlers.all?(&:success?) ? @exit_code : 1
        logger.info("Exit: #{status}")
        exit status
      end
    end
    # :nocov:

    # == Логировать статус
    #
    # Логирует текущее состояние обработчиков (DEBUG уровень).
    # Формат: "Total:N Running:M Finihsed:K. TERM"
    #
    # :nocov:
    def log_status
      total = handlers.size
      running = handlers.count(&:running?)
      finihsed = handlers.count(&:finished?)
      term_text = terminating? ? 'TERM' : ''
      logger.debug("Total:#{total} Running:#{running} Finihsed:#{finihsed} Success:#{handlers.map {|h| h.success?}.to_s}. #{term_text}".strip)
    end
    # :nocov:
  end
end
