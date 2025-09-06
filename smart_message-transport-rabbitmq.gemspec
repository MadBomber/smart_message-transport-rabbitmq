# frozen_string_literal: true

require_relative "lib/smart_message/transport/rabbitmq/version"

Gem::Specification.new do |spec|
  spec.name = "smart_message-transport-rabbitmq"
  spec.version = SmartMessage::Transport::Rabbitmq::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "RabbitMQ transport adapter for SmartMessage"
  spec.description = "A RabbitMQ transport implementation for the SmartMessage library, providing reliable message queuing and routing capabilities with support for various exchange types and advanced routing patterns."
  spec.homepage = "https://github.com/MadBomber/smart_message-transport-rabbitmq"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/MadBomber/smart_message-transport-rabbitmq"
    spec.metadata["changelog_uri"] = "https://github.com/MadBomber/smart_message-transport-rabbitmq/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "smart_message"

  spec.add_development_dependency "debug_me"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rubocop"

end
