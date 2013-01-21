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
      before_save :cache_sitta_save
      after_save :cache_sitta_after_save
      before_destroy :cache_sitta_destory
    end

    module ClassMethods

      def cs_time_col
        @_cs_time_col ||= (self.superclass.respond_to?(:cs_time_col) ? self.superclass.cs_time_col : :created_at)
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

    def cache_sitta_save
      self.cache_work(true)
    end

    def cache_sitta_after_save
      self.post_cache_work
    end

    def cache_sitta_destory
      self.cache_work(false)
    end

    #Updates the cache after update of any cache sittaed item.
    def cache_work(alive)
      original_clazz = self.class
      # Also have to go through all its super objects till the super objects aren't cache sittaed
      # this is because the new updated object for a sub class, could have also been in a cache for
      # said sub class, but also in a cache for its super.
      cur_clazz = original_clazz
      while(cur_clazz.respond_to? :destroy_cache_hash)

        #AR - Clear all caches related to the old route_id
        cur_clazz.destroy_cache_hash(:route_id => self.route_id_was(cur_clazz).to_s)

        #AR - Clear all caches related to the old time col value
        # Don't run if time is nil. It can't be index by time
        # if time is nil anyway.
        time_was = self.cs_time_col_was(cur_clazz)
        if time_was
          cur_clazz.destroy_time_caches(time_was)
        end

        # AR - Clear all index caches where old object state is in scope
        cur_clazz.destroy_cache_hash(:obj => self)

        cur_clazz = cur_clazz.superclass
      end

      #AR - For Safety this will not recurse upwards for the extra cache maintenance
      extra_cache_maintenance(alive)
    end

    #Sense the checking the scope requires the object to be in the database, this has to be called in case the new version that has been 
    #saved fits into any cache's scope. The above call to clear index caches is basically the object_was call, while this is just the call 
    #for the update object.
    #Also in case they are using the updated_at as the time stamp time destroy must happen here.
    def post_cache_work
      original_clazz = self.class
      cur_clazz = original_clazz

      while(cur_clazz.respond_to? :destroy_cache_hash)
        #AR - Clear all caches related to the new route_id
        cur_clazz.destroy_cache_hash(:route_id => self.route_id(cur_clazz).to_s)

        #AR - Clear all caches related to the new time col value
        # Don't run if time is nil. It can't be index by time
        # if time is nil anyway.
        time = self.cs_time_col(cur_clazz)
        if time
          cur_clazz.destroy_time_caches(time)
        end

        # AR - Clear all index caches where new object state is in scope
        cur_clazz.destroy_cache_hash(:obj => self)

        cur_clazz = cur_clazz.superclass
      end

      extra_cache_maintenance(true)

    end

    #AR - For Safety this will not recurse upwards for the extra cache maintenance
    def extra_cache_maintenance alive
      method = (@_cache_extra_maintance || Proc.new{})
      method.call
    end

  end
end