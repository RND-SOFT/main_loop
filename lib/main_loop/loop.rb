require 'logger'
require 'timeouter'

module MainLoop
  # Сигналы для терминации
  # @return [Array<String>]
  TERM_SIGNALS = %w[INT TERM].freeze

  # = MainLoop::Loop
  #
  # Главный цикл управления, запускает обработку сигналов, обрабатывает события из Bus.
  #
  # == Жизненный цикл
  #
  # 1. {#run} устанавливает {#install_signal_handlers}
  # 2. {#start_loop_forever} запускает цикл обработки событий
  # 3. События из Bus обрабатываются через case:
  #    - 'term' → {#term}
  #    - 'crash' → {#crash}
  #    - /sig:/ → {#signal}
  #    - /reap:/ → {#reap}
  #    - nil → reap_children (timeout)
  # 4. {Dispatcher#reap} получает завершенные процессы
  # 5. {Dispatcher#tick} проверяет необходимость принудительного завершения
  #
  # == Пример использования
  #
  #   bus = MainLoop::Bus.new
  #   dispatcher = MainLoop::Dispatcher.new(bus, timeout: 10)
  #   loop = MainLoop::Loop.new(bus, dispatcher)
  #
  #   loop.run(30)  # запуск с таймаутом 30 секунд
  #
  # == См. также
  # - {MainLoop::Bus} — канал событий
  # - {MainLoop::Dispatcher} — координирует обработчики
  # - {MainLoop::ProcessHandler} — обработчики процессов
  # - {MainLoop::ThreadHandler} — обработчики потоков

  class Loop
    attr_reader :logger

    # == Инициализация
    #
    # @param bus [Bus] канал событий
    # @param dispatcher [Dispatcher] диспетчер обработчиков
    # @param logger [Logger] логгер (по умолчанию Logger.new(nil))
    def initialize(bus, dispatcher, logger: nil)
      STDOUT.sync = true
      STDERR.sync = true
      @bus = bus
      @dispatcher = dispatcher
      @logger = logger || Logger.new(nil)
    end

    # == Запуск цикла
    #
    # Устанавливает обработчики сигналов и запускает {#start_loop_forever}.
    #
    # @param timeout [Numeric] таймаут цикла в секундах (0 = бесконечный)
    # @raise [StandardError] если произошла ошибка в цикле
    def run(timeout = 0)
      install_signal_handlers(@bus)

      start_loop_forever(timeout)
    rescue StandardError => e
      # :nocov:
      logger.fatal("Exception in Main Loop: #{e.inspect}")
      exit!(2)
      # :nocov:
    end

    # == Главный цикл обработки событий
    #
    # Цикл с ограниченным временем работы (через Timeouter).
    #
    # Интервал ожидания событий:
    #   wait = [[(timeout / 2.5), 5].min, 5].max
    # Минимум 5 секунд (даже при timeout = 0)
    #
    # @param timeout [Numeric] таймаут цикла в секундах (0 = бесконечный)
    def start_loop_forever(timeout = 0)
      wait = [[(timeout / 2.5), 5].min, 5].max
      Timeouter.loop(timeout) do
        event = @bus.gets(wait)
        logger.debug("command:#{event}")

        case event
        when 'term'
          term(event)
        when 'crash'
          crash(event)
        when /sig:/
          signal(event)
        when /reap:/
          reap(event)
        when nil
          logger.debug('Empty event: reaping...')
        else
          logger.debug("unknown event:#{event}")
        end

        @dispatcher.reap(reap_children) rescue nil
        @dispatcher.tick
      end
    end

    # == Установка обработчиков сигналов
    #
    # Устанавливает trap для TERM, INT и CLD.
    # Сигналы отправляются в Bus через отдельные потоки.
    #
    # :nocov:
    def install_signal_handlers(bus)
      TERM_SIGNALS.each do |sig|
        trap(sig) do |*_args|
          Thread.new(bus) {|b| b.puts "sig:#{sig}" }
        end
      end

      trap 'CLD' do
        Thread.new(bus) {|b| b.puts 'sig:CLD' }
      end
    end
    # :nocov:

    # == Обработка сигнала
    #
    # @param command [String] команда вида "sig:NAME"
    def signal(command)
      _, sig = command.split(':')
      logger.debug("signal:#{sig}")

      if TERM_SIGNALS.include?(sig)
        @dispatcher.term
      elsif sig == 'CLD'
        # nothing to do child will reap later
      else
        logger.info("unhandled signal:#{sig}")
      end
    end

    # == Инициировать терминацию
    #
    # Передает команду терминации диспетчеру (если не уже терминация).
    #
    # @param _command [String] команда (Unused)
    def term(_command)
      @dispatcher.term unless @dispatcher.terminating?
    end

    # == Отправить сигнал аварийного завершения
    #
    # Передает команду crash диспетчеру.
    #
    # @param _command [String] команда (Unused)
    def crash(_command)
      @dispatcher.crash
    end

    # == Обработка завершения процесса
    #
    # Парсит команду "reap:id:status" и отправляет в диспетчер.
    #
    # @param command [String] команда вида "reap:id:status"
    def reap(command)
      _, id, status = command.split(':')
      @dispatcher.reap_by_id(id, status)
    end

    # == Сбор завершенных процессов
    #
    # Проходит по всем PID обработчиков и собирает их статусы через wait2.
    # Дополнительно собирает все оставшиеся дочерние процессы (wait2(-1)).
    #
    # == Особенности обработки ECHILD
    #
    # Если процесс завершился и был "съеден" другой системой (например, родительский процесс
    # вызвал Process.wait в on_term обработчике), то Process.wait2(pid) вызовет Errno::ECHILD.
    # Это нормальное поведение в Unix/Linux когда PID больше не существует в таблице процессов.
    #
    # В этом случае:
    # - Мы добавляем [pid, nil] в результат, чтобы отметить, что процесс не найден
    # - Обработка продолжается для остальных процессов в списке
    # - Это предотвращает "зависание" обработки всех остальных процессов
    #
    # Пример сценария (см. test_process.rb):
    # 1. ProcessHandler запускает процесс с PID 123
    # 2. При терминации вызывается on_term(pid) в обработчике
    # 3. on_term вызывает Process.wait(pid) и "съедает" статус
    # 4. Позже reap_children пытается wait2(123) и получает ECHILD
    # 5. Обработка продолжается для других процессов, а 123 помечается как [123, nil]
    #
    # == Логика обработки
    #
    # Метод проходит по каждому PID из @dispatcher.pids:
    # - wait2(pid) возвращает [pid, status] если процесс найден
    # - wait2(pid) возвращает nil если процесс еще не завершился
    # - wait2(pid) вызывает Errno::ECHILD если PID уже не существует
    #
    # Для каждого случая:
    # - Нам возвращается [pid, status] -> добавляем в results
    # - Возвращается nil -> ничего не добавляем (не завершился)
    # - ECHILD -> добавляем [pid, nil] (PID не найден, съеден другой системой)
    #
    # После обработки всех известных PID, делается wait2(-1) для сбора
    # любых оставшихся дочерних процессов (с таймаутом 2 секунды).
    #
    # @return [Array<Array>] массив пар (pid, status)
    def reap_children
      results = []

      @dispatcher.pids.each do |pid|
        begin
          if (result = self.wait2(pid))
            results << result
          end
        rescue Errno::ECHILD
          # Процесс "съеден" другой системой (например, Process.wait вызван в on_term)
          # или процесс уже завершился и pid больше не существует
          # Добавляем [pid, nil] чтобы отметить его и продолжить обработку остальных
          results << [pid, nil]
        end
      end

      Timeouter.loop(2) do
        unless (result = self.wait2(-1))
          break
        end

        results << result
      end

      results
    rescue Errno::ECHILD
      results
    end

    # == Ожидание завершения процесса
    #
    # Обертка для Process.wait2 с флагом WNOHANG.
    #
    # @param pid [Integer] PID процесса для ожидания
    # @return [Array<Integer, Process::Status>|nil] пара (pid, status) или nil если нет завершенных
    # :nocov:
    def wait2(pid)
      Process.wait2(pid, ::Process::WNOHANG)
    end
    # :nocov:
  end
end
