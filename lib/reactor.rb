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
require "reactor/event"

module Reactor
  SUBSCRIBERS = {}.with_indifferent_access
  BASE_VALIDATOR = -> (_event) { } # default behavior is to not actually validate anything

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

  #
  # If you want, you can inject your own validator block in `config/initializers/reactor.rb`
  #
  # Reactor.validator -> (event) { Validator.new(event).validate! }
  #
  # If not, the default behavior is to do nothing. (see Reactor::BASE_VALIDATOR)
  #
  def validator(block = nil)
    @validator = block if block.present?

    @validator || BASE_VALIDATOR
  end
end
