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
      before_save :cs_get_state
      before_destroy :cs_get_state
      after_commit :cache_work
    end

    module ClassMethods

      def cs_time_col
        @_cs_time_col ||= (self.superclass.respond_to?(:cs_time_col) ? self.superclass.cs_time_col : :created_at)
      end

      def cs_watch_assoc
        if @_cs_watch_assoc.nil?
          cs_watch_assoc = (self.superclass.respond_to?(:cs_watch_assoc) ? self.superclass.cs_watch_assoc : [])
          if !(cs_watch_assoc.class.eql?(Array))
            @_cs_watch_assoc = [] << cs_watch_assoc
          else
            @_cs_watch_assoc = cs_watch_assoc
          end
        end

        @_cs_watch_assoc
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
        if route_id_cur && !route_id_was.eql?(route_id_cur)
          destroy_cache_hash(:route_id => route_id_cur)
        end
      end

      def destroy_time_caches time_was, time_cur

        time_strings_hash = {}

        destroy_time_caches_loop time_was, time_strings_hash
        destroy_time_caches_loop time_cur, time_strings_hash

      end

      def destroy_time_caches_loop time, time_strings_hash
        if time
          time = fs_time_parse time

          time_string = ""

          time.each do |time_part|
            #Update String
            time_string = time_string + time_part.to_s
            #Check to make sure this hasn't been cleared before.
            if time_strings_hash[time_string].nil?
              destroy_cache_hash(:time => time_string)
            end
            #Mark the string as have been being cleared.
            time_strings_hash[time_string] = true
            #Add the ending slash for next update.
            time_string = time_string + '/'
          end
        end
      end

      def fs_time_parse time 
        #Break it up to mirror how it is represented in the cache
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

    def cs_get_state
      # @cs_original_new_rec = self.new_record?
      # @cs_original_klass_was = self.class
      fs_get_state
    end

    #Updates the cache after update of any cache sittaed item.
    def cache_work options={}
      assoc_already_visited = options[:assoc_already_visited] || {}
      old_state = (assoc_already_visited.size < 1) ? @_fs_old_state : nil
      new_state = self


      if old_state
        original_klass_was = old_state.class
      else
        original_klass_was = nil
      end

      original_klass_cur = new_state.has_attribute?('type') ? ((new_state.type.present? ? new_state.type : nil) || new_state.class) : new_state.class
      if original_klass_cur.class.eql?(String)
        original_klass_cur = original_klass_cur.constantize
      end

      klass_hash = {}

      if original_klass_was
        fs_get_all_klasses original_klass_was, klass_hash
      end

      if !self.destroyed? || (assoc_already_visited.size > 0)
        fs_get_all_klasses original_klass_cur, klass_hash
      end

      klass_hash.each do |name, klass|

        cache_work_real_work klass, old_state, new_state, assoc_already_visited

      end

    end

    def fs_get_all_klasses klass, klass_hash
      cur_klass = klass
      #Now go up the chain of inheritance till you hit Active::Record Base
      while(cur_klass.respond_to? :destroy_cache_hash)

        klass_hash[cur_klass.to_s] = cur_klass

        cur_klass = cur_klass.superclass

      end
    end

    def cache_work_real_work klass, old_state, new_state, assoc_already_visited={}

      if old_state
        route_id_was = old_state.send("route_id",klass).to_s
        time_was = old_state.send("cs_time_col_was", klass)
      else
        time_was = nil
        route_id_was = nil
      end

      if !new_state.destroyed? || assoc_already_visited.size > 0
        route_id_cur = new_state.send("route_id",klass).to_s
        time_cur = new_state.send("cs_time_col", klass)
      else
        time_cur = nil
        route_id_cur = nil
      end

      #AR - Clear all caches related to the old or new route_id
      klass.destory_object_cache(route_id_was, route_id_cur)

      #AR - Clear all caches related to the old or new time col value
      # Don't run if both times are nil. It can't be index by time
      # if time is nil anyway.
      if time_cur || time_was
        klass.destroy_time_caches(time_was, time_cur)
      end

      # AR - Clear all index caches
      klass.destroy_cache_hash()

      if klass.cs_watch_assoc
        cache_sitta_assoc_update(:belongs_to, klass, self, old_state, assoc_already_visited)
        cache_sitta_assoc_update(:has_one, klass, self, old_state, assoc_already_visited)
      end

    end

    def cache_sitta_assoc_update association, klass, new_state, old_state, assoc_already_visited={}
      klass.reflect_on_all_associations(association).each do |a|
        if klass.cs_watch_assoc.include?(a.name)

          assoc_already_visited[old_state] = true

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
          assoc_obj.cache_work :assoc_already_visited => assoc_already_visited
        end
      end
    end

    def cache_sitta_assoc_watch object
      self.cache_work
      object.cache_work
    end

  end
end