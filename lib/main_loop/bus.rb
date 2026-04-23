require 'monitor'
require 'timeouter'

# = MainLoop::Bus
#
# Потоко-безопасный канал обмена событиями между компонентами на основе IO.pipe.
#
# Использует {MonitorMixin} для синхронизации доступа и {Timeouter} для таймаутов.
# Буферизация строк для корректного парсинга построчно.
#
# == События
#
# События — это строки, отправляемые через {puts}. События читаются методами {gets}
# и {gets_nonblock}. Разделитель строк — newline ("\n").
#
# == Пример использования
#
#   bus = MainLoop::Bus.new
#   bus.puts("term")         # Отправить событие
#   event = bus.gets(5)      # Получить событие с таймаутом 5 секунд
#
# == См. также
# - {MainLoop::Loop} — потребитель событий
# - {MainLoop::Dispatcher} — потребитель событий
# - {MonitorMixin} — реализация потоко-безопасности

module MainLoop
  class Bus
    include MonitorMixin
    # Константа конца строки (end of line)
    # @return [String]
    EOL = "\n".freeze

    attr_reader :read, :write

    # == Инициализация
    #
    # Создает IO.pipe, настраивает синхронный режим, инициализирует буфер.
    #
    # @example
    #   bus = MainLoop::Bus.new
    #
    # @!attribute [r] read
    #   @return [IO] конец канала для чтения
    # @!attribute [r] write
    #   @return [IO] конец канала для записи
    def initialize
      super()
      @read, @write = IO.pipe
      @read.sync = true
      @write.sync = true
      @buffer = ''
    end

    # == Проверка наличия событий
    #
    # Проверяет, есть ли события в канале.
    #
    # @param timeout [Numeric] таймаут ожидания в секундах
    # @return [Boolean] true если событий нет, false если событие доступно
    def empty?(timeout = 0)
      !wait_for_event(timeout)
    end

    # == Закрытие канала
    #
    # Закрывает оба конца канала (read и write).
    # Ошибки закрытия игнорируются (rescue nil).
    #
    # @example
    #   bus.close
    def close
      @write.close rescue nil
      @read.close rescue nil
    end

    # == Проверка закрытости канала
    #
    # @return [Boolean] true если любой конец канала закрыт
    def closed?
      @write.closed? || @read.closed?
    end

    # == Отправка события
    #
    # Отправляет строку в канал с потоко-безопасной синхронизацией.
    # Автоматически добавляет конец строки.
    #
    # @param str [String] событие для отправки
    # @example
    #   bus.puts("term")
    #   bus.puts("reap:123:0")
    def puts(str)
      synchronize do
        @write.puts str.to_s
      end
    end

    # == Ожидание события
    #
    # Использует IO.select для ожидания события в канале.
    #
    # @param timeout [Numeric] таймаут ожидания в секундах
    # @return [Array<IO>|nil] результат IO.select или nil при таймауте
    def wait_for_event(timeout)
      IO.select([@read], [], [], timeout)
    end

    # == Блокирующее чтение события
    #
    # Блокирует до получения события или таймаута.
    # Использует {Timeouter.loop} для ограничения времени ожидания.
    #
    # @param timeout [Numeric] таймаут ожидания в секундах
    # @return [String|nil] прочитанное событие (без символа новой строки) или nil при таймауте
    def gets(timeout)
      Timeouter.loop(timeout) do |t|
        line = gets_nonblock if wait_for_event(t.left)
        return line if line
      end
    end

    # == Неблокирующее чтение строки
    #
    # Читает посимвольно до конца строки (EOL).
    # Буферизует символы и возвращает полную строку.
    #
    # @return [String|nil] строка (без EOL и пробелов по краям) или nil если нет данных
    def gets_nonblock
      while (ch = @read.read_nonblock(1))
        @buffer << ch
        next if ch != MainLoop::Bus::EOL

        line = @buffer
        @buffer = ''
        return line&.strip
      end
      nil
    rescue IO::WaitReadable
      nil
    end
  end
end
