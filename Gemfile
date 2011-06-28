source :rubygems
source "http://sulair-rails-dev.stanford.edu"

gemspec

group :development do
  if File.exists?(mygems = File.join(ENV['HOME'],'.gemfile'))
    instance_eval(File.read(mygems))
  end
end