#
# DRY up strict event & data assertions.
#
# Example:
#
#  expect { some_thing }.to publish_event(:some_event, actor: this_user, target: this_object)
#
RSpec::Matchers.define :publish_event do |name, **data|
  supports_block_expectations

  match do |block|
    defaults = {:actor => anything}

    allow(Reactor::Event).to receive(:publish)

    block.call

    expect(Reactor::Event).to have_received(:publish).with(name, **(defaults.merge(data))).at_least(:once)
  end
end


#
# DRY up multi-event assertions. Unfortunately can't test key-values with this at the moment.
#
# Example:
#
#  expect { some_thing }.to publish_events(:some_event, :another_event)
#
RSpec::Matchers.define :publish_events do |*names|
  supports_block_expectations

  match do |block|
    defaults = {:actor => anything}

    allow(Reactor::Event).to receive(:publish)

    block.call

    names.each do |name|
      expect(Reactor::Event).to have_received(:publish).with(name, anything).at_least(:once)
    end
  end
end

RSpec::Matchers.define :subscribe_to do |name, **data|
  supports_block_expectations

  match do
    block_arg.call if block_arg.present?
    Reactor::Event.publish(name, **data)
  end
end
