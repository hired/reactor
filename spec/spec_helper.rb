require 'rubygems'
require 'bundler/setup'
require 'pry'

require 'support/active_record'
require 'support/shared_examples'
require 'sidekiq'
require 'sidekiq/testing/inline'
require 'sidekiq/api'

require 'simplecov'
SimpleCov.start do
  add_filter "/testing/"
end

require 'reactor'
require 'reactor/testing/matchers'

require 'rspec/its'

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  include Reactor::Publishable
  include Reactor::Subscribable
end

class Pet < ApplicationRecord
end

class ArbitraryModel < ApplicationRecord
end

REDIS_URL = ENV["REDISTOGO_URL"] || ENV["REDIS_URL"] || "redis://localhost:6379/4"

ActionMailer::Base.delivery_method = :test

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


RSpec.configure do |config|
  # some (optional) config here

  config.before(:each) do
    Reactor.test_mode!
    Reactor.clear_test_subscribers!
    ActionMailer::Base.deliveries.clear
  end

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
