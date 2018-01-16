#
# Run this before specs if you want to speed up tests by trading out code coverage into subscribers
#
def stub_reactor_subscribers
  Reactor::SUBSCRIBERS.each do |_event, subscribers|
    subscribers.each do |subscriber|
      allow(subscriber).to receive(:perform_where_needed)
    end
  end
end

#
# If stubbing out reactor in test, use this method to re-enable a specific subscriber
# to test its logic.
#
def allow_reactor_subscriber(subscribable_class)
  worker_module = "Reactor::StaticSubscribers::#{subscribable_class}".safe_constantize
  worker_module.constants.each do |worker_class_name|

    worker_class = "Reactor::StaticSubscribers::#{subscribable_class}::#{worker_class_name}".
        safe_constantize

    allow(worker_class).to receive(:perform_where_needed).and_call_original
  end

  yield if block_given? # yes you can use block syntax if you want
end