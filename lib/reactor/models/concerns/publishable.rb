# frozen_string_literal: true

module Reactor::Publishable
  extend ActiveSupport::Concern

  included do
    after_commit :schedule_events, if: :persisted?, on: :create
    after_commit :reschedule_events_on_update, if: :persisted?, on: :update
  end

  def publish(name, data = {})
    Reactor::Event.publish(name, data.merge(actor: self))
  end

  def reschedule_events
    self.class.events.each do |name, data|
      reschedule(name, data)
    end
  end

  module ClassMethods
    def publishes(name, data = {})
      events[name] = data
    end

    def events
      @events ||= {}
    end
  end

  private

  def reschedule_events_on_update
    self.class.events.each do |name, data|
      attr_changed_method = data[:watch] || data[:at]
      reschedule(name, data) if previous_changes[attr_changed_method]
    end
  end

  def reschedule(name, data)
    if data[:at]
      event = event_data_for_signature(data).merge(
        was: previous_changes[data[:at]].try(:first) || send("#{data[:at]}_was")
      )
      Reactor::Event.reschedule(name, event) if should_fire_reactor_event?(data)
    end
  end

  def schedule_events
    self.class.events.each do |name, data|
      event = event_data_for_signature(data)
      Reactor::Event.publish(name, event) if should_fire_reactor_event?(data)
    end
  end

  def should_fire_reactor_event?(data, handler_name = :enqueue_if)
    handler = data[handler_name]
    case handler
    when Proc
      instance_exec(&handler)
    when Symbol
      send(handler)
    when NilClass
      true
    end
  end

  def event_data_for_signature(signature)
    signature.merge(
      actor: (signature[:actor] ? send(signature[:actor]) : self),
      target: (signature[:target] ? self : nil),
      at: (signature[:at] ? send(signature[:at]) : nil)
    ).except(:watch, :enqueue_if)
  end
end
