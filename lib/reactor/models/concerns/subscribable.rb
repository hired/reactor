module Reactor::Subscribable
  extend ActiveSupport::Concern

  def self.included(base)
    if base.included_modules.include?(Sidekiq::Worker) && !base.instance_methods.include?(:perform)
      base.send(:define_method, :perform) do |method, data|
        event = Reactor::Event.new(data)
        self.class.public_send(method, event)
      end
    end
  end

  module ClassMethods
    def on_event(*args, &block)
      options = args.extract_options!
      event, method = args
      (Reactor::SUBSCRIBERS[event.to_s] ||= []).push(StaticSubscriberFactory.create(event, method, {source: self}.merge(options), &block))
    end
  end

  class StaticSubscriberFactory

    def self.create(event, method = nil, options = {}, &block)
      handler_class_prefix = event == '*' ? 'Wildcard': event.to_s.camelize
      i = 0
      begin
        new_class = "#{handler_class_prefix}Handler#{i}"
        i+= 1
      end while Reactor::StaticSubscribers.const_defined?(new_class)

      klass = Class.new do
        include Sidekiq::Worker

        class_attribute :method, :delay, :source, :in_memory, :dont_perform

        def perform(data)
          return :__perform_aborted__ if dont_perform && !Reactor::TEST_MODE_SUBSCRIBERS.include?(source)

          event = Reactor::Event.new(data)

          if method.is_a?(Symbol)
            if source.included_modules.include?(Sidekiq::Worker)
              source.perform_in(delay, method, data)
            else
              source.delay_for(delay).send(method, event)
            end
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

      Reactor::StaticSubscribers.const_set(new_class, klass)

      klass.tap do |k|
        k.method = method || block
        k.delay = options[:delay] || 0
        k.source = options[:source]
        k.in_memory = options[:in_memory]
        k.dont_perform = Reactor.test_mode?
      end
    end
  end
end
