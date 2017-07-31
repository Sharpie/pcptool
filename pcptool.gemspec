# -*- encoding: utf-8 -*-
require File.join([File.dirname(__FILE__),'lib','pcptool'])

Gem::Specification.new do |s|
  s.name = 'pcptool'
  s.version = Pcptool::VERSION
  s.summary = 'Pure Ruby interface for the Puppet Communications Protocol'
  s.description = <<-EOS
The pcptool library provides Ruby tools for sending and receiving messages via
the Puppet Communications Protocol (PCP).
EOS

  s.license = 'Apache-2.0'
  s.authors = ['Charlie Sharpsteen']
  s.email = 'source@sharpsteen.net'
  s.homepage = 'https://github.com/Sharpie/pcptool'

  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 2.1.0'

  s.files = Dir['lib/**/*.rb']
  s.require_paths = ['lib']

  s.add_development_dependency 'rake',                          '~> 12.0'
  s.add_development_dependency 'rspec',                         '~> 3.1'
  s.add_development_dependency 'yard',                          '~> 0.9'
end
# vim:ft=ruby
