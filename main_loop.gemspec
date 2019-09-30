$:.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'main_loop/version'

Gem::Specification.new 'main_loop' do |spec|
  spec.version       = ENV['BUILDVERSION'].to_i > 0 ? "#{MainLoop::VERSION}.#{ENV['BUILDVERSION'].to_i}" : MainLoop::VERSION
  spec.authors       = ['Samoilenko Yuri']
  spec.email         = ['kinnalru@gmail.com']
  spec.description   = spec.summary = 'Main Loop implementation to control subprocesses and threads'
  spec.homepage      = 'https://github.com/RnD-Soft/main_loop'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z lib/main_loop.rb lib/main_loop README.md LICENSE features`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.add_development_dependency 'bundler', '~> 2.0', '>= 2.0.1'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec_junit_formatter'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'simplecov-console'

  spec.add_runtime_dependency 'timeouter'
end

