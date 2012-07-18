module FlagpoleSitta
  module CacheSitta
    extend ActiveSupport::Concern

    #When forcing a call back into a class from a module you must do it inside an include block
    included do
      before_save :cache_sitta_save
      before_destroy :cache_sitta_destory
    end

    module ClassMethods

      def initialize_index_array_cache

        clazz = self

        flag = {:space => - 1}

        Rails.cache.write("#{clazz}/IndexArray/Flag", flag)

        flag

      end

      def update_index_array_cache key

        clazz = self

        flag = Rails.cache.read("#{clazz}/IndexArray/Flag")

        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_index_array_cache
        end

        #AR - update the array's end point
        flag[:space] = flag[:space] + 1
       
        #AR - write out the new index at the end of the array
        Rails.cache.write("#{clazz}/IndexArray/#{flag[:space]}", {:key => key})

        #AR - update flag in the cache
        Rails.cache.write("#{clazz}/IndexArray/Flag", flag)

      end

      def each_index_cache &block

        clazz = self

        flag = Rails.cache.read("#{clazz}/IndexArray/Flag")
        
        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_index_array_cache
        end

        #AR - If there aren't any index do nothing.
        #Else wise loop through every index.
        #If it actually does exist then yield.
        for i in 0..flag[:space] do
          hash = Rails.cache.read("#{clazz}/IndexArray/#{i}")
          if hash
            yield hash[:key]
          end
        end

        nil

      end

      def destroy_index_array_cache

        clazz = self

        each_index_cache do |key|
          Rails.cache.delete(key)
        end

        Rails.cache.delete("#{clazz}/IndexArray/Flag")
      end

      def initialize_show_array_cache route_id

        clazz = self

        #AR - Its negative one to stop the for loops in the each method if its empty
        flag = {:space => - 1}

        Rails.cache.write("#{clazz}/#{route_id}/ShowArray/Flag", flag)

        flag

      end

      def update_show_array_cache key, route_id

        clazz = self

        flag = Rails.cache.read("#{clazz}/#{route_id}/ShowArray/Flag")

        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_show_array_cache(route_id)
        end

        #AR - Update the array's end point
        flag[:space] = flag[:space] + 1

        #AR - Write out the new index at the end of the array
        Rails.cache.write("#{clazz}/#{route_id}/ShowArray/#{flag[:space]}", {:key => key})

        #AR - Update flag in the cache
        Rails.cache.write("#{clazz}/#{route_id}/ShowArray/Flag", flag)

      end

      def each_show_cache route_id, &block

        clazz = self

        flag = Rails.cache.read("#{clazz}/#{route_id}/ShowArray/Flag")
        
        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_show_array_cache(route_id)
        end

        #AR - If there aren't any shows caches do nothing, this happens when space is -1.
        #Else wise loop through every caches.
        #If it actually does exist then yield.
        for i in 0..flag[:space] do
          hash = Rails.cache.read("#{clazz}/#{route_id}/ShowArray/#{i}")
          if hash
            yield hash[:key]
          end
        end

        nil

      end

      def destroy_show_array_cache route_id

        clazz = self

        each_show_cache route_id do |k|
          Rails.cache.delete(k)
        end

        Rails.cache.delete("#{clazz}/#{route_id}/ShowArray/Flag")
      end

    end

    def cache_sitta_save
      self.cache_work(true)
    end

    def cache_sitta_destory
      self.cache_work(false)
    end

    def cache_work(alive)
      original_clazz = self.class
      # Also have to go through all its super objects till the super objects aren't cache sittaed
      # this is because the new updated object for a sub class, could have also been in a cache for
      # said sub class, but also in a cache for its super.
      clazz = original_clazz
      while(clazz.respond_to? :destroy_show_array_cache)

        #AR - Clear all caches related to the old route_id
        clazz.destroy_show_array_cache(self.try(:send, ("#{clazz.route_id}_was")).to_s)
        #AR - Clear all caches related to the new route_id just in case
        clazz.destroy_show_array_cache(self.try(:send, ("#{clazz.route_id}")).to_s)
        #AR - If the new and old are the same All that will happen on the second call is that
        #it will write the flag out and then destroy it. A very tiny bit of work
        #for a great amount of extra protection.

        # AR - Remember to include models_in_index in your helper call in the corresponding index cache.
        clazz.destroy_index_array_cache

        clazz = clazz.superclass
      end

      #AR - For Safety this will not recurse upwards for the extra cache maintenance
      extra_cache_maintenance(alive)

    end

    #AR - For Safety this will not recurse upwards for the extra cache maintenance
    def extra_cache_maintenance alive
      method = (@_cache_extra_maintance || Proc.new{})
      method.call
    end

  end
end