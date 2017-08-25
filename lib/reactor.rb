require "active_record"
require "active_support/hash_with_indifferent_access"
require "action_mailer"

require "reactor/version"
require "reactor/errors"
require "reactor/static_subscribers"
require "reactor/workers/concerns/configuration"
require "reactor/workers"
require "reactor/subscription"
require "reactor/models"
require "reactor/controllers"
require "reactor/event"

# FIXME: should only be included in test environments
require "reactor/testing"

module Reactor
  SUBSCRIBERS = {}.with_indifferent_access

  module_function

  def subscribers
    SUBSCRIBERS
  end

  def add_subscriber(event_name, worker_class)
    subscribers[event_name] ||= []
    subscribers[event_name] << worker_class
  end

  def subscribers_for(event_name)
    Array(subscribers[event_name]) + Array(subscribers['*'])
  end

  def subscriber_namespace
    Reactor::StaticSubscribers
  end
end
