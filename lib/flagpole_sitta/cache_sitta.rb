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
      before_destroy :cache_sitta_destory
    end

    module ClassMethods

      #Determines if its for an index array or show array.
      def mid_key_gen route_id
        if route_id
          mid_key = "#{route_id}/ShowArray"
        else
          mid_key = "IndexArray"
        end
      end

      #Creates the 'array' in the cache.
      def initialize_array_cache route_id = nil

        mid_key = mid_key_gen route_id

        clazz = self

        flag = {:space => - 1}

        Rails.cache.write("#{clazz}/#{mid_key}/Flag", flag)

        flag

      end

      #Updates the 'array' in the cache.
      def update_array_cache key, route_id = nil

        mid_key = mid_key_gen route_id

        clazz = self

        flag = Rails.cache.read("#{clazz}/#{mid_key}/Flag")

        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_array_cache route_id
        end

        #AR - update the array's end point
        flag[:space] = flag[:space] + 1
       
        #AR - write out the new index at the end of the array
        Rails.cache.write("#{clazz}/#{mid_key}/#{flag[:space]}", {:key => key})

        #AR - update flag in the cache
        Rails.cache.write("#{clazz}/#{mid_key}/Flag", flag)

      end

      #Loops through the array in the cache.
      def each_cache route_id = nil, &block

        mid_key = mid_key_gen route_id

        clazz = self

        flag = Rails.cache.read("#{clazz}/#{mid_key}/Flag")
        
        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_array_cache route_id
        end

        #AR - If there aren't any index do nothing.
        #Else wise loop through every index.
        #If it actually does exist then yield.
        for i in 0..flag[:space] do
          hash = Rails.cache.read("#{clazz}/#{mid_key}/#{i}")
          if hash
            yield hash[:key]
          end
        end

        nil

      end

      #Nukes all corresponding caches for a given array.
      def destroy_array_cache route_id = nil

        mid_key = mid_key_gen route_id

        clazz = self

        each_cache route_id do |key|
          Rails.cache.delete(key)
        end

        Rails.cache.delete("#{clazz}/#{mid_key}/Flag")
      end

    end

    def cache_sitta_save
      self.cache_work(true)
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
      clazz = original_clazz
      while(clazz.respond_to? :destroy_array_cache)

        #AR - Clear all caches related to the old route_id
        clazz.destroy_array_cache(self.try(:send, ("#{clazz.route_id}_was")).to_s)
        #AR - Clear all caches related to the new route_id just in case
        clazz.destroy_array_cache(self.try(:send, ("#{clazz.route_id}")).to_s)
        #AR - If the new and old are the same All that will happen on the second call is that
        #it will write the flag out and then destroy it. A very tiny bit of work
        #for a great amount of extra protection.

        # AR - Remember to include models_in_index in your helper call in the corresponding index cache.
        clazz.destroy_array_cache

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