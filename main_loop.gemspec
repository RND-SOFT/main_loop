require './lib/main_loop/version'

Gem::Specification.new 'main_loop' do |spec|
  spec.version       = ENV['BUILDVERSION'].to_i > 0 ? "#{MainLoop::VERSION}.#{ENV['BUILDVERSION'].to_i}" : MainLoop::VERSION
  spec.authors       = ['Samoilenko Yuri']
  spec.email         = ['kinnalru@gmail.com']
  spec.description   = spec.summary = 'Timeouter is advisory timeout helper without any background threads.'
  spec.homepage      = 'https://github.com/RnD-Soft/main_loop'
  spec.license       = 'MIT'

  spec.files         = %w(lib/timeouter.rb lib/timeouter/timer.rb lib/timeouter/version.rb README.md LICENSE).reject do |f|
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

