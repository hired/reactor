class Reactor::Event < Reactor::Jobs::Base

  def initialize(data = {})
    super(data.stringify_keys)
  end

  def perform(data)
    data = data.with_indifferent_access
    data.merge!(fired_at: Time.current)
    fire_database_driven_subscribers(data)
    fire_block_subscribers(data)
  end

  def method_missing(method, *args)
    if method.to_s.include?('=')
      try_setter(method, *args)
    else
      try_getter(method)
    end
  end

  def self.publish(name, data = {})
    perform_later({name: name.to_s}.merge(data))
  end

  private

  def try_setter(method, object, *args)
    arguments.first[method.to_s.gsub('=','')] = object
  end

  def try_getter(method)
    arguments.first[method.to_s]
  end

  def fire_database_driven_subscribers(data)
    #TODO: support more matching?
    Reactor::Subscriber.where(event_name: [name, '*']).each do |subscriber|
      Reactor::Jobs::SubscriberJob.perform_later subscriber, data
    end
  end

  def fire_block_subscribers(data)
    ((Reactor::SUBSCRIBERS[name] || []) | (Reactor::SUBSCRIBERS['*'] || [])).each { |s| s.perform_where_needed(data) }
  end
end
