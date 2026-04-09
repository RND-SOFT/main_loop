# YARD-документация для main_loop
# Основной модуль библиотеки для управления субпроцессами и потоками

require 'main_loop/bus'
require 'main_loop/loop'
require 'main_loop/dispatcher'
require 'main_loop/process_handler'
require 'main_loop/thread_handler'

# = MainLoop
#
# Главный модуль библиотеки для управления субпроцессами и потоками.
#
# Основные компоненты:
# - {MainLoop::Bus} — канал обмена событиями между компонентами
# - {MainLoop::Dispatcher} — координация обработчиков и управление жизненным циклом
# - {MainLoop::Loop} — главный цикл обработки событий и сигналов
# - {MainLoop::Handler} — абстрактный базовый класс для обработчиков
# - {MainLoop::ProcessHandler} — управление субпроцессами
# - {MainLoop::ThreadHandler} — управление потоками
#
# == Пример использования
#
#   require 'main_loop'
#   require 'logger'
#
#   logger = Logger.new(STDOUT)
#   logger.level = Logger::DEBUG
#
#   bus = MainLoop::Bus.new
#   dispatcher = MainLoop::Dispatcher.new(bus, timeout: 10, logger: logger)
#   mainloop = MainLoop::Loop.new(bus, dispatcher, logger: logger)
#
#   MainLoop::ProcessHandler.new dispatcher, 'worker', retry_count: 3, logger: logger do
#     sleep 2
#     exit! 0
#   end
#
#   mainloop.run
#
# == См. также
# - {MainLoop::Bus}
# - {MainLoop::Dispatcher}
# - {MainLoop::Loop}
# - {MainLoop::Handler}
# - {MainLoop::ProcessHandler}
# - {MainLoop::ThreadHandler}

module MainLoop

  class << self

  end

end
