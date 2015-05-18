require "reactor/version"
require 'active_job'
require "reactor/models/concerns/subscribable"
require "reactor/models/concerns/publishable"
require "reactor/models/concerns/optionally_subclassable"
require "reactor/models/subscriber"
require "reactor/controllers/concerns/resource_actionable"

module Reactor
  SUBSCRIBERS = {}
  TEST_MODE_SUBSCRIBERS = Set.new
  @@test_mode = false

  module StaticSubscribers
  end

  module Jobs
  end

  def self.test_mode?
    @@test_mode
  end

  def self.test_mode!
    @@test_mode = true
  end

  def self.disable_test_mode!
    @@test_mode = false
  end

  def self.in_test_mode
    test_mode!
    (yield if block_given?).tap { disable_test_mode! }
  end

  def self.enable_test_mode_subscriber(klass)
    TEST_MODE_SUBSCRIBERS << klass
  end

  def self.disable_test_mode_subscriber(klass)
    TEST_MODE_SUBSCRIBERS.delete klass
  end

  def self.with_subscriber_enabled(klass)
    enable_test_mode_subscriber klass
    yield if block_given?
    disable_test_mode_subscriber klass
  end
end

# Temporarily avoid Rails 4.2.0 deprecation warning
if ActiveRecord::VERSION::STRING > '4.2'
  ActiveRecord::Base.raise_in_transactional_callbacks = true
end

ActiveRecord::Base.send(:include, Reactor::Subscribable)
ActiveRecord::Base.send(:include, Reactor::Publishable)

require "reactor/jobs/base"
require "reactor/event"
require "reactor/arguments"
require "reactor/jobs/subscriber_job"

