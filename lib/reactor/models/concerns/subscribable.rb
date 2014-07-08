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

    class << self
      def create(event, method = nil, options = {}, &block)
        klass = Class.new do
          include Sidekiq::Worker

          class_attribute :method, :delay, :source, :in_memory, :dont_perform

          def perform(data)
            return :__perform_aborted__ if dont_perform && !Reactor::TEST_MODE_SUBSCRIBERS.include?(source)
            event = Reactor::Event.new(data)
            if method.is_a?(Symbol)
              source.delay_for(delay).send(method, event)
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

        class_name = compose_class_name(options[:source], event, method)
        Reactor::StaticSubscribers.const_set(class_name, klass)

        klass.tap do |k|
          k.method = method || block
          k.delay = options[:delay] || 0
          k.source = options[:source]
          k.in_memory = options[:in_memory]
          k.dont_perform = Reactor.test_mode?
        end
      end

      def compose_class_name(klass, event, method)
        class_name = klass.try(:name) || 'AnonymousClass'
        method_name = method.is_a?(Symbol) ? method.to_s.camelize : 'Block'
        event = event == '*' ? 'Wildcard': event.to_s.camelize

        new_class = prepare_class_string(class_name, event, method_name)
        new_class << block_number(new_class) if method_name == 'Block'
        new_class
      end

      def prepare_class_string(class_name, event, method)
        "#{class_name}On#{event}Calls#{method}"
      end

      def block_number(class_name)
        i = 0
        i += 1 while Reactor::StaticSubscribers.const_defined?("#{class_name}#{i}")
        i.to_s
      end
    end

    private_class_method :compose_class_name,
                         :prepare_class_string,
                         :block_number
  end
end
