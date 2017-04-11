# Reactor Change Log

0.14.0
-----------
Remove any use of `Sidekiq::Delayed` extensions. mperham [specifically discourages their use](https://github.com/mperham/sidekiq/wiki/Delayed-extensions), and they do not work in Rails 5 development mode. They serialize & deserialize the monkey-patched objects as `!ruby/object:` , which is [possible in YAML](http://yaml.org/YAML_for_ruby.html#objects), but causes all kinds of problems in a real application.

0.12.2
-----------
Correctly handles exceptions in `with_subscriber_enabled`

0.12.1
-----------
Fix unicode encoding protection to allow valid multi-byte unicode characters

0.12.0
-----------
Use `__data__` as the internal data hash. THIS _MAY BE_ A BREAKING CHANGE.

If someone wants to use the key `data` for their event attributes, it would get confused with the internal event data. The internal event data is now called `__data__`.
Some users of this library access event.data directly. This is a breaking change for them.

0.11.4
-----------
Fixes an issue related to class reloading in Rails development and test modes

0.11.2
-----------
Safely handle bad UTF-8 encoded strings passed in as event arguments

0.11.1
-----------
Bug fix for namespaced Subscribable objects

0.11.0
-----------
Static Subscriber class names have changed to be more deterministic. THIS _MAY BE_ A BREAKING CHANGE.
See https://github.com/hired/reactor/issues/40 for background info.

Previously, when you added an `on_event :foo` block to an object, say `MyObject`, Reactor would dynamically generate a Sidekiq worker class named `Reactor::StaticSubscribers::FooHandler0`.

In 0.11.0, the naming of this dynamically generated worker class has changed to `Reactor::StaticSubscribers::MyObject::FooHandler`.
If you require more than one `on_event` block for the same event, you must name the handler so that it is unique and deterministic: i.e. `on_event :foo, handler_name: :do_better` otherwise an exception will be raised at load time.
This example would generate a `Reactor::StaticSubscribers::MyObject::DoBetter` class for the worker.

Because the worker class names are changing, when deploying this change it's important that your Sidekiq queue not have any pending jobs with the old naming scheme, otherwise they will fail to deserialize!
