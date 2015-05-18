require 'rubygems'
require 'bundler/setup'
require 'pry'
require 'timecop'

require 'support/active_record'
require 'reactor'
require 'reactor/testing/matchers'

require 'rspec/its'

GlobalID.app = 'reactor'

RSpec.configure do |config|
  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = "random"

  config.after(:each) do
    Reactor::Subscriber.delete_all
  end
end
