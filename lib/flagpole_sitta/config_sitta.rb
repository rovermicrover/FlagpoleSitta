module FlagpoleSitta
  module ConfigSitta

    extend ActiveSupport::Concern

    def route_id klass = nil
      klass ||= self.class
      self.try(:send, ("#{klass.route_id}"))
    end

    def route_id_was klass = nil
      klass ||= self.class
      self.try(:send, ("#{klass.route_id}_was"))
    end

    def fs_get_state
      if self.new_record?
        @_fs_old_state = nil
      else
        incl = self.class.respond_to?(cs_watch_assoc) ? self.class.cs_watch_assoc : nil
        @_fs_old_state = self.class.includes(incl).find(self.id)
      end
    end

    module ClassMethods

      def route_id
        @_fs_route_id ||= (self.superclass.respond_to?(:route_id) ? self.superclass.route_id : "id")
      end

      def has_existence_hash options = {}
        @_fs_route_id ||= options[:route_id]
        @_eh_update_ehnum_after ||= options[:update_num_after]
        @_eh_ehnum_col ||= options[:num_column]
        include FlagpoleSitta::ExistenceHash
      end

      def has_brackets_retrieval options = {}
        @_br_safe_content ||= options[:safe_content]
        @_br_value_field ||= options[:value]
        @_br_key_field ||= options[:key]
        @_br_default_value ||= options[:default_value]
        include FlagpoleSitta::BracketRetrieval
      end

      def cache_sitta options = {}
        @_fs_route_id ||= options[:route_id]
        @_cs_time_col ||= options[:time_column]
        @_cs_watch_assoc ||= options[:watch_assoc]
        include FlagpoleSitta::CacheSitta
      end

    end

  end
end

ActiveRecord::Base.send(:include, FlagpoleSitta::ConfigSitta)