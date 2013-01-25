module FlagpoleSitta
  ##
  #CacheSitta's main purpose is to make it easier to effectively fragment cache in dynamic fashions in Rails.
  #
  #When ever a cache is created it is associated with any model and/or record you tell it to be from the view helper method. When that model and/or record is updated all it’s associated caches are cleared.
  #
  #Flagpole also expects you to put all your database calls into Procs/Lamdbas. This makes it so that your database calls wont have to happen unless your cache hasn’t been created. Thus speeding up response time and reducing database traffic.
  module CacheSitta
    extend ActiveSupport::Concern

    included do
      before_save :fs_get_state
      before_destroy :fs_get_state
      after_commit :cache_work
    end

    module ClassMethods

      def cs_time_col
        @_cs_time_col ||= (self.superclass.respond_to?(:cs_time_col) ? self.superclass.cs_time_col : :created_at)
      end

      def cs_watch_assoc
        @_cs_watch_assoc ||= (self.superclass.respond_to?(:cs_watch_assoc) ? self.superclass.cs_watch_assoc : [])
        if !(@_cs_watch_assoc.class.eql?(Array))
          @_cs_watch_assoc = [] << @_cs_watch_assoc
        end
      end

      def get_model model
        model || self
      end

      #Updates the 'array' in the cache.
      #Options :route_id which determines the type of mid_key
      def update_cache_hash key, options={}

        model = get_model options[:model]

        if options[:time]
          cachehash = CacheHash.new(model, options[:time])
        else
          cachehash = CacheHash.new(model, options[:route_id])
        end

        cachehash.add(key, options)

      end

      #Nukes all corresponding caches for a given array.
      def destroy_cache_hash options={}

        model = get_model options[:model]

        if options[:time]
          cachehash = CacheHash.new(model, options[:time])
        else
          cachehash = CacheHash.new(model, options[:route_id])
        end

        cachehash.destory(options)

      end

      def destory_object_cache route_id_was, route_id_cur
        if route_id_was
          destroy_cache_hash(:route_id => route_id_was)
        end
        if !route_id_was.eql?(route_id_cur)
          destroy_cache_hash(:route_id => route_id_cur)
        end
      end

      def destroy_time_caches time_was, time_cur

        time_was = fs_time_parse time_was
        time_cur = fs_time_parse time_cur

        time_was_string = ""
        time_cur_string = ""

        time_was.each_index do |i|

          time_was_string = time_was_string + time_was[i].to_s
          time_cur_string = time_cur_string + time_cur[i].to_s
          if time_was_string
            destroy_cache_hash(:time => time_was_string)
          end
          if !time_was_string.eql?(time_cur_string)
            destroy_cache_hash(:time => time_cur_string)
          end

          time_was_string = time_was_string + '/'
          time_cur_string = time_cur_string + '/'

        end

      end

      def fs_time_parse time 
        time = [time.strftime('%Y').to_i,time.strftime('%m').to_i,time.strftime('%d').to_i,time.strftime('%H').to_i]
      end

    end

    def cs_time_col klass = nil
      klass ||= self.class
      self.try(:send, ("#{klass.cs_time_col}"))
    end

    def cs_time_col_was klass = nil
      klass ||= self.class
      self.try(:send, ("#{klass.cs_time_col}_was"))
    end

    #Updates the cache after update of any cache sittaed item.
    def cache_work assoc_already_visited={}
      original_klass_was = @_fs_old_state.class
      original_klass_cur = self.destroyed? ? nil.class : self.class
      #Have to go through all possibilities so have
      #to go down and up the chain of inheritance here.
      klass_hash = {}

      fs_get_all_klasses original_klass_cur, klass_hash
      fs_get_all_klasses original_klass_was, klass_hash

      klass_hash.each do |name, klass|

        cache_work_real_work klass, assoc_already_visited

      end

      @old_state = nil

    end

    def fs_get_all_klasses klass, klass_hash
      cur_klass = klass
      #Now go up the chain of inheritance till you hit Active::Record Base
      while(cur_klass.respond_to? :destroy_cache_hash)

        klass_hash[cur_klass.to_s] = cur_klass

        cur_klass = cur_klass.superclass

      end
    end

    def cache_work_real_work klass, assoc_already_visited={}
      new_state = self.destroyed? ? nil : self
      old_state = @_fs_old_state

      if old_state
        time_was = old_state.send("cs_time_col_was", klass)
        route_id_was = old_state.send("route_id",klass).to_s
      else
        time_was = nil
        route_id_was = nil
      end

      if new_state
        route_id_cur = new_state.send("route_id",klass).to_s
        time_cur = new_state.send("cs_time_col", klass)
      else
        time_cur = nil
        route_id_cur = nil
      end

      #AR - Clear all caches related to the old or new route_id

      klass.destory_object_cache(route_id_was, route_id_cur)

      #AR - Clear all caches related to the old or new time col value
      # Don't run if time is nil. It can't be index by time
      # if time is nil anyway.
      if time_cur && time_was
        klass.destroy_time_caches(time_was, time_cur)
      end

      # AR - Clear all index caches
      klass.destroy_cache_hash()

      if klass.cs_watch_assoc
        cache_sitta_assoc_update(:belongs_to, klass, new_state, old_state, assoc_already_visited)
        cache_sitta_assoc_update(:has_one, klass, new_state, old_state, assoc_already_visited)
      end

    end

    def cache_sitta_assoc_update association, klass, new_state, old_state, assoc_already_visited={}
      klass.reflect_on_all_associations(association).each do |a|
        if klass.cs_watch_assoc.include?(a.name)

          cache_sitta_assoc_obj_update old_state, a.name, assoc_already_visited
          cache_sitta_assoc_obj_update new_state, a.name, assoc_already_visited

        end
      end
    end

    def cache_sitta_assoc_obj_update state, assoc_name, assoc_already_visited={}
      if state
        begin
          assoc_obj = state.send(assoc_name)
        rescue
          assoc_obj = nil
        end

        if assoc_obj && !(assoc_already_visited[assoc_obj])
          assoc_already_visited[assoc_obj] = true
          assoc_obj.cache_work assoc_already_visited
        end
      end
    end

    def cache_sitta_assoc_watch object
      self.cache_work
      object.cache_work
    end

  end
end