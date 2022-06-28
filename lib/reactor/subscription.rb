module Reactor
  class Subscription

    attr_reader :source, :event_name, :action, :handler_name, :delay, :worker_class,
                :deprecated, :sidekiq_options

    def self.build_handler_name(event_name, handler_name_option = nil)
      if handler_name_option
        handler_name_option.to_s.camelize
      elsif event_name == '*'
        'WildcardHandler'
      else
        "#{event_name.to_s.camelize}Handler"
      end
    end

    def initialize(options = {}, &block)
      @source = options[:source]
      @handler_name = self.class.build_handler_name(
        options[:event_name], options[:handler_name]
      )

      @event_name = options[:event_name]
      @action = options[:action] || block

      @delay = options[:delay].to_i
      @deprecated = !!options[:deprecated]
      @sidekiq_options = options[:sidekiq_options] || {}
      build_worker_class
    end

    def handler_defined?
      namespace.const_defined?(handler_name) &&
        namespace.const_get(handler_name).send(Reactor.parents_method).include?(Reactor.subscriber_namespace)
    end

    def event_handler_names
      @event_handler_names ||= []
    end

    def namespace
      return @namespace if @namespace
      @namespace = generate_namespace
    end

    def generate_namespace
      module_chain.reduce(Reactor.subscriber_namespace) do |mod, name|
        unless mod.const_defined?(name, false)
          mod.const_set(name, Module.new)
        end
        mod.const_get(name)
      end
    end

    def mailer_subscriber?
      !!(source < ActionMailer::Base)
    end

    private

    def module_chain
      source.name.split('::')
    end

    def build_worker_class

      worker_class = mailer_subscriber? ? build_mailer_worker : build_event_worker
      namespace.send(:remove_const, handler_name) if handler_defined?
      namespace.const_set(handler_name, worker_class)
      @worker_class = namespace.const_get(handler_name)
    end

    def build_event_worker
      subscription = self
      Class.new(Reactor::Workers::EventWorker) do
        self.source = subscription.source
        self.action = subscription.action
        self.delay  = subscription.delay
        self.deprecated  = subscription.deprecated
        self.sidekiq_options subscription.sidekiq_options
      end
    end

    def build_mailer_worker
      subscription = self
      Class.new(Reactor::Workers::MailerWorker) do
        self.source = subscription.source
        self.action = subscription.action
        self.delay  = subscription.delay
        self.deprecated  = subscription.deprecated
        self.sidekiq_options subscription.sidekiq_options
      end
    end

  end
end
