# -*- encoding: utf-8 -*-
require 'rake'

lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
  
Gem::Specification.new do |s|
  s.name        = "checksum-tools"
  s.version     = "0.6.3"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Michael Klein"]
  s.email       = ["mbklein@stanford.edu"]
  s.summary     = "Checksum creation and verification tools"
  s.description = "Contains classes and executable files to generate and verify checksums"
 
  s.required_rubygems_version = ">= 1.3.6"
  
  # Runtime dependencies
  s.add_dependency "progressbar"
  
  # Bundler will install these gems too if you've checked out checksum-tools source from git and run 'bundle install'
  # It will not add these as dependencies if you require checksum-tools for other projects
  s.add_development_dependency "lyberteam-devel", ">=0.2.1"
  s.add_development_dependency "rake", ">=0.8.7"
  s.add_development_dependency "rcov"
  s.add_development_dependency "rdoc"
  s.add_development_dependency "rspec", "< 2.0" # We're not ready to upgrade to rspec 2
  s.add_development_dependency "ruby-debug"
  s.add_development_dependency "yard"
 
  s.files        = FileList['lib/**/*.rb', 'bin/*', '[A-Z]*'].to_a
  s.bindir       = 'bin'
  s.require_path = 'lib'
end