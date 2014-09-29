# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'yoleaux/version'

Gem::Specification.new do |spec|
  spec.name          = "yoleaux"
  spec.version       = Yoleaux::VERSION
  spec.authors       = ["David Kendal"]
  spec.email         = ["yoleaux@dpk.io"]
  spec.summary       = %q{An IRC bot.}
  spec.homepage      = ""

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"

  spec.add_runtime_dependency "httparty", "0.13.1"
  spec.add_runtime_dependency "nokogiri", "1.6.1"
  spec.add_runtime_dependency "execjs", "2.2.0"
  spec.add_runtime_dependency "tzinfo", "1.2.1"
  spec.add_runtime_dependency "tzinfo-data"
end
