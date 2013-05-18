module FlagpoleSitta
  module ConfigSitta

    extend ActiveSupport::Concern

    def route_id klass = nil
      klass ||= self.class
      self.try(:send, ("#{klass.route_id_field}"))
    end

    def route_id_was klass = nil
      klass ||= self.class
      self.try(:send, ("#{klass.route_id_field}_was"))
    end

    def fs_get_state
      if self.new_record?
        @_fs_old_state = nil
      else
        incl = self.class.respond_to?(:cs_watch_assoc) ? self.class.cs_watch_assoc : nil
        @_fs_old_state = self.class.includes(incl).find(self.id)
      end
    end

    module ClassMethods

      def route_id_field
        @_fs_route_id_field ||= (self.superclass.respond_to?(:route_id_field) ? self.superclass.route_id_field : "id")
      end

      def has_existence_hash options = {}
        @_fs_route_id_field ||= options[:route_id]
        @_br_safe_content ||= options[:safe_content]
        @_br_value_field ||= options[:bracket_value]
        @_br_default_value ||= options[:default_value]
        include FlagpoleSitta::ExistenceHash
      end

      def cache_sitta options = {}
        @_fs_route_id_field ||= options[:route_id]
        @_cs_time_col ||= options[:time_column]
        @_cs_watch_assoc ||= options[:watch_assoc]
        include FlagpoleSitta::CacheSitta
      end

    end

  end
end

ActiveRecord::Base.send(:include, FlagpoleSitta::ConfigSitta)