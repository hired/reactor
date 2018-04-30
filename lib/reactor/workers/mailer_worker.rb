# frozen_string_literal: true

# MailerWorker has a bit more to do than EventWorker. It has to run the event, then if the
# output is a Mail::Message or the like it needs to deliver it like ActionMailer would
module Reactor
  module Workers
    class MailerWorker
      include Reactor::Workers::Configuration

      def perform(data)
        raise_unconfigured! unless configured?
        return :__perform_aborted__ unless should_perform?
        event = Reactor::Event.new(data)

        msg = if action.is_a?(Symbol)
                source.send(action, event)
              else
                source.new.instance_exec(event, &action)
              end

        deliverable?(msg) ? deliver(msg) : msg
      end

      def deliver(msg)
        if msg.respond_to?(:deliver_now)
          # Rails 4.2/5.0
          msg.deliver_now
        else
          # Rails 3.2/4.0/4.1 + Generic Mail::Message
          msg.deliver
        end
      end

      def deliverable?(msg)
        msg.respond_to?(:deliver_now) || msg.respond_to?(:deliver)
      end
    end
  end
end
