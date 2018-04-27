# frozen_string_literal: true

module Reactor
  module Subscribable
    extend ActiveSupport::Concern

    module ClassMethods
      def on_event(*args, &block)
        options = args.extract_options!
        options[:event_name], options[:action] = args
        options[:action] ||= block
        options[:source] = self
        add_subscription(options)
      end

      private

      def add_subscription(options = {})
        event_name = options[:event_name]
        check_for_duplicate_subscription!(event_name, options[:handler_name_option])
        subscription = Subscription.new(options)

        handler_names << subscription
        handler_names.uniq!

        Reactor.add_subscriber(event_name, subscription.worker_class)
      end

      def handler_names
        @handler_names ||= []
      end

      def duplicate_subscription?(handler_name)
        handler_names.include?(handler_name)
      end

      def check_for_duplicate_subscription!(event_name, handler_name_option = nil)
        handler_name = Subscription.build_handler_name(event_name, handler_name_option)
        if duplicate_subscription?(handler_name)
          raise EventHandlerAlreadyDefined, "A Reactor event named #{handler_name} already has been defined on #{static_subscriber_namespace}.
             Specify a `:handler_name` option on your subscriber's `on_event` declaration to name this event handler deterministically."
        end
      end
    end
  end
end
