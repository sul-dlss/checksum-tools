# -*- encoding: utf-8 -*-

lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require "checksum-tools"

Gem::Specification.new do |s|
  s.name        = "checksum-tools"
  s.version     = Checksum::Tools::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Michael Klein"]
  s.email       = ["mbklein@stanford.edu"]
  s.summary     = "Checksum creation and verification tools"
  s.description = "Contains classes and executable files to generate and verify checksums"
  s.executables = ["checksum-tools"]
  
  s.required_rubygems_version = ">= 1.3.6"
  
  # Runtime dependencies
  s.add_dependency "progressbar"
  s.add_dependency "net-ssh"
  s.add_dependency "net-sftp"
  
  # Bundler will install these gems too if you've checked out checksum-tools source from git and run 'bundle install'
  # It will not add these as dependencies if you require checksum-tools for other projects
  s.add_development_dependency "rake", ">=0.8.7"
  s.add_development_dependency "rdoc"
  s.add_development_dependency "rspec"
  s.add_development_dependency "yard"
 
  s.files        = Dir['lib/**/*.rb']+Dir['bin/*']+Dir['[A-Z]*']
  s.bindir       = 'bin'
  s.require_path = 'lib'
end