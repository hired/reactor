module Reactor
  module Workers
    module Configuration
      extend ActiveSupport::Concern

      CONFIG = [:source, :action, :delay, :deprecated]

      included do
        include Sidekiq::Worker
        
        class_attribute *CONFIG
      end

      class_methods do
        def configured?
          CONFIG.all? {|field| !self.send(field).nil? }
        end

        def perform_where_needed(data)
          if deprecated
            return
          elsif delay > 0
            event_queue.perform_in(delay, data)
          else
            event_queue.perform_async(data)
          end
          source
        end

        def event_queue
          queue_override = ENV['REACTOR_QUEUE']
          queue_override.present? ? set(queue: queue_override) : self
        end
      end

      def configured?
        self.class.configured?
      end

      def perform(data)
        raise_unconfigured! unless configured?
        return :__perform_aborted__ unless should_perform?
        event = Reactor::Event.new(data)
        if action.is_a?(Symbol)
          source.send(action, event)
        else
          action.call(event)
        end
      end

      def should_perform?
        true
      end

      private

      def raise_unconfigured!
        settings = Hash[CONFIG.map {|s| [s, self.class.send(s)] }]
        raise UnconfiguredWorkerError.new(
            "#{self.class.name} is not properly configured! Here are the settings: #{settings}"
        )
      end
    end
  end
end