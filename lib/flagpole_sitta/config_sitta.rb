module FlagpoleSitta
  module ConfigSitta

    extend ActiveSupport::Concern

    module ClassMethods

      def route_id
        @_route_id || (self.superclass.respond_to?(:route_id) ? self.superclass.route_id : nil)  || "id"
      end

      def has_existance_hash options = {}
        @_route_id ||= options[:route_id] ? options[:route_id].to_s : @_route_id
        include FlagpoleSitta::ExistanceHash
      end

      def has_brackets_retrieval options = {}
        @_safe_content = options[:safe_content] ? options[:safe_content] : @_safe_content
        @_value_field = options[:value] ? options[:value].to_s : @_value_field
        @_key_field = options[:key] ? options[:key].to_s : @_key_field
        @_default_value = options[:default_value] ? options[:default_value] : @_default_value
        include FlagpoleSitta::BracketRetrieval
      end

      def cache_sitta options = {}
        @_route_id = options[:route_id] ? options[:route_id].to_s : @_route_id
        include FlagpoleSitta::CacheSitta
      end

    end

  end
end

ActiveRecord::Base.send(:include, FlagpoleSitta::ConfigSitta)