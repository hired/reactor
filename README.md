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

  Static subscribers like these are automatically placed into Sidekiq and executed in the background

  It's also possible to run a subscriber block in memory like so

```ruby
on_event :any_event, in_memory: true do |event|
  event.target.do_something_about_it_and_make_the_user_wait!
end
```

  You may also have Sidekiq process a subscriber block on a specific queue or supply any other Sidekiq::Worker options accordingly.

```ruby
on_event :event_with_ui_bound, sidekiq_options: { queue: 'highest_priority' } do |event|
  speedily_execute!
end
```

#### ResourceActionable

    Enforce a strict 1:1 match between your event model and database model with this controller mixin.


```ruby
class PetsController < ApplicationController
  include Reactor::ResourceActionable
  actionable_resource :@pet

  # GET /pets
  # GET /pets.json
  def index
    @pets = current_user.pets

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @pets }
    end
  end

  def show
    @pet = current_user.pets.find(params[:id])
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @pet }
    end
  end
end

```

Now your index action (and any of the other RESTful actions in that controller) will fire a useful event for you to bind to and log.

*Important* Reactor::ResourceActionable has one major usage constraints:

Your controller *must* have a method called "action_event" with this signature.
```ruby
def action_event(name, options = {})
  # Here's what ours looks like, but yours may look different.
  actor = options[:actor] || current_user
  actor.publish(name, options.merge(default_action_parameters))
  #where default_action_parameters includes things like ip_address, referrer, user_agent
end
```

Once you write your own action_event to describe your event data model's base attributes, your ResourceActionable endpoints will now fire events that map like so (for the example above):

<dl>
<dt>index =></dt>
<dd>"pets_indexed"</dd>
</dl>

<dl>
<dt>show =></dt>
<dd>"pet_viewed", target: @pet</dd>
</dl>

<dl>
<dt>new =></dt>
<dd>"new_pet_form_viewed"</dd>
</dl>

<dl>
<dt>edit =></dt>
<dd> "edit_pet_form_viewed", target: @pet</dd>
</dl>

<dl>
<dt>create =></dt>
<dd> when valid => "pet_created", target: @pet, attributes: params[:pet]
<br />
  when invalid => "pet_create_failed", errors: @pet.errors, attributes: params[:pet]</dd>
</dl>

<dl>
<dt>update =></dt>
<dd>
when valid => "pet_updated", target: @pet, changes: @pet.previous_changes.as_json
<br />
  when invalid => "pet_update_failed", target: @pet,
                  errors: @pet.errors.as_json, attributes: params[:pet]
</dd>
</dl>

<dl>
<dt>destroy =></dt>
<dd>"pet_destroyed", last_snapshot: @pet.as_jsont</dd>
</dl>


##### What for?

If you're obsessive about data like us, you'll have written a '*' subscriber that logs every event fired in the system. With information-dense resource information logged for each action a user performs, it will be trivial for a data analyst to determine patterns in user activity. For example, with the above data being logged for the pet resource, we can easily
* determine which form field validations are constantly being hit by users
* see if there are any fields that are consistently ignored on that form until later
* recover data from the last_snapshot of a destroyed record
* write a small conversion funnel analysis to see who never makes it back to a record to update it
* bind arbitrary logic anywhere in the codebase (see next example) to that specific request without worrying about the logic being run during the request (all listeners are run in the background by Sidekiq)

For example, in an action mailer.

```ruby
class MyMailer < ActionMailer::Base
  include Reactor::EventMailer

  on_event :pet_created do |event|
    @user = event.actor
    @pet = event.target
    mail to: @user.email, subject: "Your pet is already hungry!", body: "feed it."
  end
end
```

Or in a model, concern, or other business logic file.

```ruby
class MyClass
  include Reactor::Subscribable

  on_event :pet_updated do |event|
     event.actor.recalculate_expensive_something_for(event.target)
  end
end
```

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

TLDR; Everything is a Sidekiq::Job, so all the same gotchas apply with regard to removing & renaming jobs that may have a live reference sitting in the queue. (AKA, you'll start seeing 'const undefined' exceptions when the job gets picked up if you've already deleted/renamed the job code.)

#### Adding Events and Subscribers

This is as easy as write + deploy. Of course your events getting fired won't have a subscriber pick them up until the new subscriber code is deployed in your sidekiq instances, but that's not too surprising.

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

