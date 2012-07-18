require File.expand_path("../lib/flagpole_sitta/version", __FILE__)

# Provide a simple gemspec so you can easily use your enginex
# project in your rails apps through git.
Gem::Specification.new do |s|
  s.name = "flagpole_sitta"
  s.version = FlagpoleSitta::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors     = ["Andrew Rove (Rover)"]
  s.email       = ["rovermicrover@gmail.com"]
  s.homepage    = "https://github.com/rovermicrover/FlagpoleSitta"
  s.summary     = "FlagpoleSitta a gem for effective dynamic caching"
  s.description = "Flagpole Sitta is a gem that main purpose is to make it easier to effectively fragment cache in dynamic fashions.\n When ever a cache is created it is associated with any model and/or record you tell it to be from the helper method. When that model and/or record is updated all it's associated cache's are cleared.\n Flagpole also expects you to put all your database calls into Procs/Lamdbas. This makes it so that your database calls wont have to happen unless your cache hasn't been created. Thus speeding up response time and reducing database traffic."

  s.files = `git ls-files`.split("\n")
  s.executables = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'

  #add dependecy here and in the engine file as a required.

  s.add_dependency('dalli')

end