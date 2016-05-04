source 'https://rubygems.org'

gemspec

if RUBY_VERSION > '1.8'
  gem 'net-ssh-krb'
  gem 'gssapi', :github => 'cbeer/gssapi'
  gem 'highline'
end

gem 'net-ssh-kerberos', :platform => :ruby_18

group :development do
  gem "rcov", :platform => :mri_18
end
