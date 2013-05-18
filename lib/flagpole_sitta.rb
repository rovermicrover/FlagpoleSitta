require "active_support/dependencies"

module FlagpoleSitta

  mattr_accessor :app_root

  def self.setup
    yield self
  end

end

require 'redis-objects'
require 'redis-mutex'
require 'flagpole_sitta/common_fs'
require 'flagpole_sitta/cache_sitta'
require 'flagpole_sitta/cache_hash'
require 'flagpole_sitta/existence_hash'
require 'flagpole_sitta/engine'
require 'flagpole_sitta/config_sitta'
require 'flagpole_sitta/controller_sitta'

ActiveRecord::Base.send(:include, FlagpoleSitta::ConfigSitta)
