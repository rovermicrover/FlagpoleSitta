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
      before_save :cache_sitta_before_update
      after_save :cache_sitta_after_update
      before_destroy :cache_sitta_before_update

      before_save :cache_sitta_before_update_assoc
      after_save :cache_sitta_after_update_assoc
      before_destroy :cache_sitta_before_update_assoc
    end

    module ClassMethods

      def cs_time_col
        @_cs_time_col ||= (self.superclass.respond_to?(:cs_time_col) ? self.superclass.cs_time_col : :created_at)
      end

      def cs_watch_assoc
        @_cs_watch_assoc ||= (self.superclass.respond_to?(:cs_watch_assoc) ? self.superclass.cs_watch_assoc : nil)
      end

      def get_model model
        model || self
      end

      #Updates the 'array' in the cache.
      #Options :route_id which determines the type of mid_key
      def update_cache_hash key, options={}

        model = get_model options[:model]

        #Don't want to save SQL injection attempts into Redis.
        #Kill them upfront just in case.
        if options[:scope]
          options[:scope] = sanitize_sql_for_conditions(options[:scope])
        end

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

      def destroy_time_caches time
        time = [time.strftime('%Y').to_i,time.strftime('%m').to_i,time.strftime('%d').to_i,time.strftime('%H').to_i]
        time_cur_string = ""
        time.each do |t|
          time_cur_string = time_cur_string + t.to_s
          destroy_cache_hash(:time => time_cur_string)
          time_cur_string = time_cur_string + '/'
        end
      end

    end

    def cs_time_col clazz = nil
      clazz ||= self.class
      self.try(:send, ("#{clazz.cs_time_col}"))
    end

    def cs_time_col_was clazz = nil
      clazz ||= self.class
      self.try(:send, ("#{clazz.cs_time_col}_was"))
    end

    def cache_sitta_before_update
      self.cache_work true
    end

    def cache_sitta_after_update
      self.cache_work false
    end

    #Updates the cache after update of any cache sittaed item.
    def cache_work before
      original_clazz = self.class
      #Have to go through all possibilities so have
      #to go down and up the chain of inheritance here.

      #Go down the chain of inheritance
      decedents = original_clazz.descendants
      cache_work_descedants before, decedents

      cur_clazz = original_clazz

      #Now go up the chain of inheritance till you hit Active::Record Base
      while(cur_clazz.respond_to? :destroy_cache_hash)

        cache_work_real_work before, cur_clazz

        cur_clazz = cur_clazz.superclass

      end

    end

    def cache_work_descedants before, decedents

      decedents.each do |d|
        cache_work_descedants before, d.descendants
        cache_work_real_work before, d
      end

    end

    def cache_work_real_work before, clazz
      if before
        ending = "_was"
      else
        ending = ""
      end
      #AR - Clear all caches related to the old or new route_id
      clazz.destroy_cache_hash(:route_id => self.send("route_id#{ending}",clazz).to_s)

      #AR - Clear all caches related to the old or new time col value
      # Don't run if time is nil. It can't be index by time
      # if time is nil anyway.
      time = self.send("cs_time_col#{ending}", clazz)
      if time
        clazz.destroy_time_caches(time)
      end

      # AR - Clear all index caches where old object state is in scope
      clazz.destroy_cache_hash(:obj => self)
    end

    def cache_sitta_before_update_assoc
      if assoc = self.class.cs_watch_assoc
        cache_work_assoc(assoc, true)
      end
    end

    def cache_sitta_after_update_assoc
      if assoc = self.class.cs_watch_assoc
        cache_work_assoc(assoc, false)
      end
    end

    def cache_work_assoc assoc, before
      if before
        state = self.class.find(self.id)
      else
        state = self
      end

      if !assoc.class.eql?(Array)
        assoc = [] << assoc
      end
      assoc = assoc.compact

      assoc.each do |a|
        assoc_objs = state.send(a)

        if !assoc_objs.class.eql?(Array)
          assoc_objs = [] << assoc_objs
        end
        assoc_objs = assoc_objs.compact

        assoc_objs.each do |ao|
          ao.cache_work(before)
        end
      end

    end

  end
end