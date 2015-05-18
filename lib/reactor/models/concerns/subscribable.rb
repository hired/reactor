module Reactor::Subscribable
  extend ActiveSupport::Concern

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

      klass = Class.new(Reactor::Jobs::Base) do

        class_attribute :method, :delay, :source, :dont_perform

        def perform(data)
          return :__perform_aborted__ if dont_perform && !Reactor::TEST_MODE_SUBSCRIBERS.include?(source)
          event = Reactor::Event.new(data)
          if method.is_a?(Symbol)
            ActiveSupport::Deprecation.silence do
              source.send(method, event)
            end
          else
            method.call(event)
          end
        end

        def self.perform_where_needed(data)
          perform_later(data)
        end
      end

      Reactor::StaticSubscribers.const_set(new_class, klass)

      klass.tap do |k|
        k.method = method || block
        k.source = options[:source]
        k.dont_perform = Reactor.test_mode?
      end
    end
  end
end
