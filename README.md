# reactor.gem

### A Sidekiq-backed pub/sub layer for your Rails app.

[![Build Status](https://travis-ci.org/hired/reactor.svg?branch=master)](https://travis-ci.org/hired/reactor)

This gem aims to provide the following tools to augment your ActiveRecord & Sidekiq stack.

 1. Barebones event API through Sidekiq to publish whatever you want
 2. Database-driven API to manage subscribers so that users may rewire whatever you let them (transactional emails, campaigns, etc...)
 3. Static/Code-driven API to subscribe a basic ruby block to an event.
 4. A new communication pattern between your ActiveRecord models that runs asynchronously through Sidekiq.
    a. describe model lifecycle events and callbacks with class-level helper methods/DSL

## Installation

Add this line to your application's Gemfile:

    gem 'reactor'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install reactor

## Usage

Well, this is evolving, so it's probably best to go read the specs as
well as below.


### Barebones API

```ruby
Reactor::Event.publish(:event_name, any: 'data', you: 'want')
```


#### Publishable

  Describe lifecycle events like so

```ruby
publishes :my_model_created
```

  Schedule an event to get published at a specific time. Note: if timestamp is a property on an ActiveRecord::Model
  then updating that property will re-schedule the firing of the event

```ruby
publishes :something_happened, at: :timestamp
```

  Schedule an event to get published at a specific time using a method to generate the timestamp and following some other property. In this case the :something_happened event will be fired 72 hours after your model is created. The event will be re-scheduled if created_at is changed.

```ruby
def reminder_email_time
  created_at + 72.hours
end

publishes :reminder_sent, at: :reminder_email_time, watch: :created_at
```

  Scheduled events can check conditionally fire -- eg: in 2 days fire reminder_email if the user hasn't already responded. Note that this check will occur at the time the event is intended to fire, after which the state of the model may have changed. 

```ruby
publishes :reminder_sent, at: :reminder_email_time, if: -> { user.responded == false }
```

  It is also possible to conditionally trigger events so that the check happens within the context of the model, at the moment an update occurs, rather than later in the context of the Reactor::Event

```ruby
publishes :model_changed_in_some_important_way, enqueue_if: -> { important_change_occurred? }
```


#### Subscribable

  You can now bind any block to an event in your models like so

```ruby
on_event :any_event do |event|
  event.target.do_something_about_it!
end
```

  Static subscribers like these are automatically placed into Sidekiq and executed in the background.

  You may also have Sidekiq process a subscriber block on a specific queue or supply any other Sidekiq::Worker options accordingly.

```ruby
on_event :event_with_ui_bound, sidekiq_options: { queue: 'highest_priority' } do |event|
  speedily_execute!
end
```
### Automatic Events

If you'd like to have events automatically fired for you around standard rails resource controller actions,
you may want to write your own downstream abstraction for it. We attempted this once and it seems unwise to presume your application would want the same thing.

It probably only makes sense if you have a real Magestic Monolith and an intentionally small team because coupling resource names to event streams makes refactoring harder.
(Though it may still be worth it for you, depending on your needs!)

### Testing

Calling `Reactor.test_mode!` enables test mode.  (You should call this as early as possible, before your subscriber classes
are declared).  In test mode, no subscribers will fire unless they are specifically enabled, which can be accomplished
by calling
```ruby
Reactor.enable_test_mode_subscriber(MyAwesomeSubscriberClass)
```

We also provide
```ruby
Reactor.with_subscriber_enabled(MyClass) do
  # stuff
end
```

for your testing convenience.

#### Matchers

You can clean up some event assertions with these somewhat imperfect matchers.

```
# DRY up strict event & data assertions.
expect { some_thing }.to publish_event(:some_event, actor: this_user, target: this_object)
```

```
# DRY up multi-event assertions. Unfortunately can't test key-values with this at the moment.
expect { some_thing }.to publish_events(:some_event, :another_event)
```


### Production Deployments

TLDR; Everything is a Sidekiq::Worker, so all the same gotchas apply with regard to removing & renaming jobs that may have a live reference sitting in the queue. (AKA, you'll start seeing 'const undefined' exceptions when the job gets picked up if you've already deleted/renamed the job code.)

#### Adding Events and Subscribers

This is as easy as write + deploy. Of course your events getting fired won't have a subscriber pick them up until the new subscriber code is deployed in your sidekiq instances, but that's not too surprising.

#### Validating Events On Publish

As of 1.0 you may inject your own validator lambda to handle the logic and flow-control of valid/invalid events.

This is entirely optional and the default behavior is to do nothing, to not validate any data being provided.

```ruby
# in config/initializers/reactor.rb
Reactor.validator -> do |event|
  Activity.build_from_event(event).validate! # you own the performance implications here
end
```

We at Hired use this to validate the event's schema as we found having stricter schema definitions 
gave us more leverage as our team grew.

By injecting your own logic, you can be as permissive or strict as you want. (Throw exceptions if you want, even.)

#### Removing Events and Subscribers

Removing an event is as simple as deleting the line of code that `publish`es it.
Removing a subscriber requires awareness of basic Sidekiq principles.

**Is the subscriber that you're deleting virtually guaranteed to have a worker for it sitting in the queue when your deletion is deployed?**

If yes -> deprecate your subscriber first to ensure there are no references left in Redis. This will prevent Reactor from enqueuing more workers for it and make it safe for you delete in a secondry deploy.
```
on_event :high_frequency_event, :do_something, deprecated: true
```

If no -> you can probably just delete the subscriber. 
In the worst case scenario, you get some background exceptions for a job you didn't intend to have run anyway. Pick your poison. 

#### Managing Queues

There will likely be more queue theory here later, but for now here are the features.

Everything is done on Sidekiq `default` queue by default.

Subscribers can opt into certain queues with `on_event :whatever, sidekiq_options: { queue: 'whatever' }` argument.

You can also override _all queue choices_ with `ENV['REACTOR_QUEUE']`. You may want to do this if you wish to contain the 'cascade' of events for more expensive or risky operations.

## Contributing

1. Fork it
2. Create your feature/fix branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

For testing Reactor itself we use Thoughtbot's [appraisal gem](https://github.com/thoughtbot/appraisal). This lets us test against multiple versions of Sidekiq, Rails, etc. To install appraisal and set up multiple dependencies, do the following:

1. `bundle install` - this will install up-to-date dependencies and appraisal
2. `appraisal install` - installs dependencies for appraisal groups
3. `appraisal rake` - runs specs for each appraisal group

## Open Source by [Hired](https://hired.com/?utm_source=opensource&utm_medium=reactor&utm_campaign=readme)

We are Ruby developers ourselves, and we use all of our open source projects in production. We always encourge forks, pull requests, and issues. Get in touch with the Hired Engineering team at _opensource@hired.com_.

