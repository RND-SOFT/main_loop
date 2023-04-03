# MainLoop

[![Gem Version](https://badge.fury.io/rb/main_loop.svg)](https://rubygems.org/gems/main_loop)
[![Gem](https://img.shields.io/gem/dt/main_loop.svg)](https://rubygems.org/gems/main_loop/versions)
[![YARD](https://badgen.net/badge/YARD/doc/blue)](http://www.rubydoc.info/gems/main_loop)

[![Test Coverage](https://api.codeclimate.com/v1/badges/baf9b1dc3dae87f7edfd/test_coverage)](https://codeclimate.com/github/RnD-Soft/main_loop/test_coverage)
[![Maintainability](https://api.codeclimate.com/v1/badges/baf9b1dc3dae87f7edfd/maintainability)](https://codeclimate.com/github/RnD-Soft/main_loop/maintainability)
[![Quality](https://lysander.rnds.pro/api/v1/badges/main_loop_quality.svg)](https://lysander.x.rnds.pro/api/v1/badges/main_loop_quality.html)
[![Outdated](https://lysander.rnds.pro/api/v1/badges/main_loop_outdated.svg)](https://lysander.x.rnds.pro/api/v1/badges/main_loop_outdated.html)
[![Vulnerabilities](https://lysander.rnds.pro/api/v1/badges/main_loop_vulnerable.svg)](https://lysander.x.rnds.pro/api/v1/badges/main_loop_vulnerable.html)

MainLoop is a simple main application implementation to control subprocesses(children) and threads.

Features:
- reaping children
- handling SIGTERM SIGINT to shutdown children(and threads) gracefully
- restarting children
- termination the children

# Usage

Example usage:

```ruby
require 'main_loop'

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

bus = MainLoop::Bus.new

dispatcher = MainLoop::Dispatcher.new(bus, logger: logger)
mainloop = MainLoop::Loop.new(bus, dispatcher, logger: logger)

MainLoop::ProcessHandler.new dispatcher, 'test1', retry_count: 3, logger: logger do
  sleep 2
  exit! 0
end

MainLoop::ProcessHandler.new dispatcher, 'test2', retry_count: 2, logger: logger do
  trap 'TERM' do
    exit(0)
  end
  sleep 2
  exit! 1
end

MainLoop::ThreadHandler.new dispatcher, 'thread2', retry_count: 0, logger: logger do
  system('sleep 15;echo ok')
end

mainloop.run
```


# Installation

It's a gem:
```bash
  gem install main_loop
```
There's also the wonders of [the Gemfile](http://bundler.io):
```ruby
  gem 'main_loop'
```


