class Reactor::Event
  include Reactor::OptionallySubclassable
  include Sidekiq::Worker

  attr_accessor :data

  def initialize(data = {})
    self.data = {}.with_indifferent_access
    data.each do |key, value|
      self.send("#{key}=", value)
    end
  end

  def perform(name, data)
    data = data.with_indifferent_access
    if Reactor.test_mode?
      Reactor.record_test_event(name, data)
    end

    if data['actor_type']
      actor = data["actor_type"].constantize.unscoped.find(data["actor_id"])
      publishable_event = actor.class.events[name.to_sym]
      ifarg = publishable_event[:if] if publishable_event
    end

    need_to_fire =  case ifarg
                    when Proc
                      actor.instance_exec(&ifarg)
                    when Symbol
                      actor.send(ifarg)
                    when NilClass
                      true
                    end

    if need_to_fire
      data.merge!(fired_at: Time.current, name: name)
      fire_database_driven_subscribers(data, name)
      fire_block_subscribers(data, name)
    end
  end

  def method_missing(method, *args)
    if method.to_s.include?('=')
      try_setter(method, *args)
    else
      try_getter(method)
    end
  end

  def to_s
    name
  end

  class << self
    def perform(name, data)
      new.perform(name, data)
    end

    def publish(name, data = {})
      message = new(data.merge(event: name))

      if message.at
        perform_at message.at, name, message.data
      else
        perform_async name, message.data
      end
    end

    def reschedule(name, data = {})
      scheduled_jobs = Sidekiq::ScheduledSet.new
      job = scheduled_jobs.detect do |job|
        next if job['class'] != self.name.to_s

        same_event_name  = job['args'].first == name.to_s
        same_at_time     = job.score.to_i == data[:was].to_i

        if data[:actor]
          same_actor =  job['args'].second['actor_type']  == data[:actor].class.name &&
                        job['args'].second['actor_id']    == data[:actor].id

          same_event_name && same_at_time && same_actor
        else
          same_event_name && same_at_time
        end
      end

      job.delete if job

      publish(name, data.except([:was, :if])) if data[:at].try(:future?)
    end
  end

  private

  def try_setter(method, object, *args)
    if object.is_a? ActiveRecord::Base
      send("#{method}_id", object.id)
      send("#{method}_type", object.class.to_s)
    else
      data[method.to_s.gsub('=','')] = object
    end
  end

  def try_getter(method)
    if polymorphic_association? method
      initialize_polymorphic_association method
    elsif data.has_key?(method)
      data[method]
    end
  end

  def polymorphic_association?(method)
    data.has_key?("#{method}_type")
  end

  def initialize_polymorphic_association(method)
    data["#{method}_type"].constantize.find(data["#{method}_id"])
  end

  def fire_database_driven_subscribers(data, name)
    #TODO: support more matching?
    Reactor::Subscriber.where(event_name: [name, '*']).each do |subscriber|
      Reactor::Subscriber.delay.fire subscriber.id, data
    end
  end

  def fire_block_subscribers(data, name)
    ((Reactor::SUBSCRIBERS[name.to_s] || []) | (Reactor::SUBSCRIBERS['*'] || [])).each { |s| s.perform_where_needed(data) }
  end
end
