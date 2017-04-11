require 'rubygems'
require 'bundler/setup'
require 'pry'

require 'support/active_record'
require 'sidekiq'
require 'sidekiq/testing/inline'
require 'sidekiq/api'
require 'reactor'
require 'reactor/testing/matchers'

require 'rspec/its'

REDIS_URL = ENV["REDISTOGO_URL"].presence || ENV["REDIS_URL"] || 'redis://127.0.0.1:6379/4'

Sidekiq.configure_server do |config|
  config.redis = { url: REDIS_URL }

  database_url = ENV['DATABASE_URL']
  if database_url
    ENV['DATABASE_URL'] = "#{database_url}?pool=25"
    ActiveRecord::Base.establish_connection
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: REDIS_URL }
end

# remove Sidekiq .delay and .delay_for extensions
# https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/rails.rb
[Sidekiq::Extensions::ActiveRecord,
 Sidekiq::Extensions::ActionMailer,
 Sidekiq::Extensions::Klass].each do |mod|
  mod.module_eval do
    remove_method :delay if respond_to?(:delay)
    remove_method :delay_for if respond_to?(:delay_for)
    remove_method :delay_until if respond_to?(:delay_until)
  end
end


RSpec.configure do |config|
  # some (optional) config here

  # Runs Sidekiq jobs inline by default unless the RSpec metadata :sidekiq is specified,
  # in which case it will use the real Redis-backed Sidekiq queue
  config.before(:each, :sidekiq) do
    Sidekiq.redis{|r| r.flushall }
    Sidekiq::Testing.disable!
  end

  config.after(:each, :sidekiq) do
    Sidekiq::Testing.inline!
  end

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = "random"
end
