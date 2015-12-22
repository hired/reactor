require "reactor/version"
require "reactor/models/concerns/publishable"
require "reactor/models/concerns/subscribable"
require "reactor/models/concerns/optionally_subclassable"
require "reactor/models/subscriber"
require "reactor/controllers/concerns/resource_actionable"
require "reactor/event"

module Reactor
  SUBSCRIBERS = {}
  TEST_MODE_SUBSCRIBERS = Set.new
  TEST_MODE_EVENTS = []
  @@test_mode = false

  module StaticSubscribers
  end

  def self.test_mode?
    @@test_mode
  end

  def self.test_mode!
    @@test_mode = true
    clear_test_events
  end

  def self.disable_test_mode!
    @@test_mode = false
    clear_test_events
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

  def self.record_test_event(name, data)
    TEST_MODE_EVENTS << [name, data]
  end

  def self.clear_test_events
    TEST_MODE_EVENTS.slice!(0..-1)
  end

  def self.test_event(name = nil, data = {})
    if TEST_MODE_EVENTS.present?
      if name.present?
        find_test_events(name, data).last
      else
        TEST_MODE_EVENTS.last.last.with_indifferent_access
      end
    end
  end

  def self.test_events(name = nil, data = {})
    if name.present?
      find_test_events(name, data)
    else
      TEST_MODE_EVENTS.map{|data| data.last.with_indifferent_access }
    end
  end

  private
    
    def self.find_test_events(name, data = {})
      data = data.with_indifferent_access
      event_list = TEST_MODE_EVENTS.select do |event_name, event_data|
        event_names_match(name, event_name) &&
        event_data_matches(data, event_data)
      end.map{|data| data.last.with_indifferent_access }
    end

    def self.event_names_match(a, b)
      return false if (a.nil? && !b.nil?) || (b.nil? && !a.nil?)
      a == b ||
      a.to_s == b ||
      a.to_sym == b
    end

    def self.event_data_matches(a, b)
      return true unless a.present?
      if a.is_a?(Hash)
        return false unless b.is_a?(Hash)
        a = a.with_indifferent_access
        b = b.with_indifferent_access
        
        a.all? do |key, val|
          if val.respond_to?(:eql?)
            b[key].eql?(val)
          else
            b[key] == val
          end
        end
      else
        a == b
      end
    end
end

# Temporarily avoid Rails 4.2.0 deprecation warning
if ActiveRecord::VERSION::STRING > '4.2'
  ActiveRecord::Base.raise_in_transactional_callbacks = true
end

ActiveRecord::Base.send(:include, Reactor::Publishable)
ActiveRecord::Base.send(:include, Reactor::Subscribable)
