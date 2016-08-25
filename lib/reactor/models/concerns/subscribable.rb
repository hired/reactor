module Reactor::Subscribable
  extend ActiveSupport::Concern

  class EventHandlerAlreadyDefined < StandardError ; end

  module ClassMethods

    def on_event(*args, &block)
      options = args.extract_options!
      event, method = args
      if subscriber = create_static_subscriber(event, method, options, &block)
        (Reactor::SUBSCRIBERS[event.to_s] ||= []).push(subscriber)
      end
    end

    private

    def create_static_subscriber(event, method = nil, options = {}, &block)
      worker_class = build_worker_class
      handler_name = handler_name(event, options[:handler_name])
      check_for_duplicate_handler_name(handler_name)

      # return if the handler has already been defined (in the case of the class being reloaded)
      return if static_subscriber_namespace.const_defined?(handler_name)
      name_worker_class worker_class, handler_name

      worker_class.tap do |k|
        k.source = self
        k.method = method || block
        k.delay = options[:delay] || 0
        k.in_memory = options[:in_memory]
        k.dont_perform = Reactor.test_mode?
      end
    end

    def handler_name(event, handler_name_option = nil)
      return handler_name_option.to_s.camelize if handler_name_option
      "#{event == '*' ? 'Wildcard': event.to_s.camelize}Handler"
    end

    def event_handler_names
      @event_handler_names ||= []
    end

    def build_worker_class
      Class.new do
        include Sidekiq::Worker

        class_attribute :method, :delay, :source, :in_memory, :dont_perform

        def perform(data)
          return :__perform_aborted__ if dont_perform && !Reactor::TEST_MODE_SUBSCRIBERS.include?(source)
          event = Reactor::Event.new(data)
          if method.is_a?(Symbol)
            source.perform_in(delay).send(method, event)
          else
            method.call(event)
          end
        end

        def self.perform_where_needed(data)
          if in_memory
            new.perform(data)
          else
            perform_async(data)
          end
        end
      end
    end

    def check_for_duplicate_handler_name(handler_name)
      if event_handler_names.include?(handler_name)
        raise EventHandlerAlreadyDefined.new(
          "A Reactor event named #{handler_name} already has been defined on #{static_subscriber_namespace}.
           Specify a `:handler_name` option on your subscriber's `on_event` declaration to name this event handler deterministically."
        )
      end
      event_handler_names << handler_name
    end

    def name_worker_class(klass, handler_name)
      static_subscriber_namespace.const_set(handler_name, klass)
    end

    def static_subscriber_namespace
      ns = self.name.demodulize
      unless Reactor::StaticSubscribers.const_defined?(ns, false)
        Reactor::StaticSubscribers.const_set(ns, Module.new)
      end

      Reactor::StaticSubscribers.const_get(ns, false)
    end
  end
end
