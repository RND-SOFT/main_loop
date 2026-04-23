require 'logger'

# = MainLoop::Handler
#
# Абстрактный базовый класс для обработчиков процессов и потоков.
#
# Определяет интерфейс и общую логику:
# - управление retry_count (количество повторов)
# - логика handle_retry
# - предикаты (finished?, success?, running?, terminating?)
# - обратный вызов on_term
#
# == Абстрактные методы (для реализации в подклассах)
#
# - {#id} — идентификатор обработчика (pid для процессов, object_id для потоков)
# - {#term} — отправка сигнала терминации
# - {#run} — запуск обработчика
# - {#kill} — принудительное завершение
# - {#reap(status)} — обработка завершения процесса/потока
#
# == См. также
# - {MainLoop::ProcessHandler} — реализация для процессов
# - {MainLoop::ThreadHandler} — реализация для потоков

module MainLoop
  class Handler
    attr_reader :dispatcher, :name, :logger

    # == Инициализация
    #
    # @param dispatcher [Dispatcher] ссылка на диспетчер
    # @param name [String] имя обработчика
    # @param retry_count [Integer, :unlimited] количество повторов после завершения
    # @param logger [Logger] логгер (по умолчанию Logger.new(nil))
    def initialize(dispatcher, name, *_args, retry_count: 0, logger: nil, **_kwargs)
      @dispatcher = dispatcher
      @name = name
      @code = 0
      @retry_count = retry_count
      @logger = logger || Logger.new(nil)
      @handler_type = 'Unknown'
    end

    # == Идентификатор (абстрактный)
    #
    # @return [String] идентификатор обработчика
    # @raise [RuntimeError] если не реализован в подклассе
    # :nocov:
    def id(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # == Терминация (абстрактный)
    #
    # Отправляет сигнал терминации обработчику.
    # @raise [RuntimeError] если не реализован в подклассе
    # :nocov:
    def term(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # == Запуск (абстрактный)
    #
    # Запускает обработчик.
    # @raise [RuntimeError] если не реализован в подклассе
    # :nocov:
    def run(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # == Принудительное завершение (абстрактный)
    #
    # Принудительно завершает обработчик.
    # @raise [RuntimeError] если не реализован в подклассе
    # :nocov:
    def kill(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # == Обработка завершения (абстрактный)
    #
    # @param status [Process::Status|nil] статус завершения
    # @raise [RuntimeError] если не реализован в подклассе
    # :nocov:
    def reap(*_args)
      raise 'not implemented!'
    end
    # :nocov:

    # == Публикация события
    #
    # Отправляет событие в канал событий диспетчера.
    #
    # @param event [String, Symbol] событие для отправки
    def publish(event)
      dispatcher.bus.puts(event)
    end

    # == Установить обратный вызов терминации
    #
    # @param block [Proc] блок кода, который будет вызван при терминации
    def on_term &block
      @on_term = block
    end

    # == Проверка завершения
    #
    # @return [Boolean] true если обработчик завершен
    # :nocov:
    def finished?
      @finished
    end
    # :nocov:

    # == Проверка успешного завершения
    #
    # @return [Boolean] true если завершен и успешно
    # :nocov:
    def success?
      finished? && @success
    end
    # :nocov:

    # == Проверка запущенности
    #
    # @return [Boolean] true если обработчик работает
    # :nocov:
    def running?
      !finished?
    end
    # :nocov:

    # == Проверка терминации
    #
    # @return [Time|nil] момент начала терминации или nil
    # :nocov:
    def terminating?
      @terminating_at
    end
    # :nocov:

    # == Логика повторов
    #
    # Управляет повторами после завершения:
    # - :unlimited — бесконечные повторы
    # - Integer >= 0 — декремент и повтор
    # - иначе — отправляет term через bus
    #
    # @return void
    def handle_retry
      if @retry_count == :unlimited
        logger.info "#{@handler_type}[#{name}] retry...."
        self.run
      elsif @retry_count && (@retry_count -= 1) >= 0
        logger.info "#{@handler_type}[#{name}] retry...."
        self.run
      else
        publish(:term)
      end
    end
  end
end
