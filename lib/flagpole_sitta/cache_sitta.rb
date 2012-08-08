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

        flag = {:space => -1, :empty => -1}

        Rails.cache.write("#{clazz}/#{mid_key}/Flag", flag)

        flag

      end

      #Updates the 'array' in the cache.
      def update_array_cache key, options={}

        mid_key = mid_key_gen options[:route_id]

        clazz = self

        flag = Rails.cache.read("#{clazz}/#{mid_key}/Flag")

        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_array_cache options[:route_id]
        end

        if flag[:empty] > -1
          #Find any empty container to use by popping it off of the top of the "stack".
          i = Rails.cache.read("#{clazz}/#{mid_key}/EmptyStack/#{flag[:empty]}")
          #Sense its going to be used remove its reference from the Stack.
          Rails.cache.delete("#{clazz}/#{mid_key}/EmptyStack/#{flag[:empty]}")
          #Update the empty on flag to now hit the newest none used container on the stack.
          flag[:empty] = flag[:empty] - 1
        else
          #AR - update the array's end point
          flag[:space] = flag[:space] + 1
          i = flag[:space]
        end
       
        #AR - write out the new index at the end of the array
        Rails.cache.write("#{clazz}/#{mid_key}/#{i}", {:key => key, :scope => options[:scope]})

        #AR - update flag in the cache
        Rails.cache.write("#{clazz}/#{mid_key}/Flag", flag)

        "#{clazz}/#{mid_key}/#{i}"

      end

      #Loops through the array in the cache.
      def each_cache route_id = nil, &block

        mid_key = mid_key_gen route_id

        clazz = self

        flag = Rails.cache.read("#{clazz}/#{mid_key}/Flag")

        #AR - If there aren't any index do nothing.
        #Else wise loop through every index.
        #If it actually does exist then yield.
        if flag
          for i in 0..flag[:space] do
            hash = Rails.cache.read("#{clazz}/#{mid_key}/#{i}")
            if hash
              yield hash
            end
          end
        end

        nil

      end

      #Nukes all corresponding caches for a given array.
      def destroy_array_cache options={}

        mid_key = mid_key_gen options[:route_id]

        clazz = self

        i = 0

        each_cache options[:route_id] do |hash|
          #A Check in Case there is some type of cache failure
          if hash.present?
            #If it has no scope, or it falls in scope
            if hash[:scope].nil? || options[:obj].in_scope(hash[:scope])
              #Get all the associated.
              associated = Rails.cache.read(hash[:key])[:associated]
              #Destroy the actually cache
              Rails.cache.delete(hash[:key])
              associated.each do |a|
                #Get the base key
                base_key = a.gsub(/\/[^\/]*\z/, "")
                #Get the flag. Capture the god damn flag!
                flag_key = base_key + "/Flag"
                #Get its location in the 'Array'
                n = a.split("/").last
                # Check in case of cache failure
                if flag = Rails.cache.read(flag_key)
                  #Add an empty spot to the 'Array'
                  flag[:empty] = flag[:empty] + 1
                  empty_stack_key = base_key + "/EmptyStack/" + flag[:empty].to_s
                  #Save the empty spot location to the 'Stack'
                  Rails.cache.write(empty_stack_key, n)
                  #Update the flag
                  Rails.cache.write(flag_key, flag)
                end

                #Finally get rid of the associated cache object.
                Rails.cache.delete(a)

              end
            #Else It is not in scope so the cache lives to fight another day!
            else
              Rails.cache.write("#{clazz}/#{mid_key}/#{i}", hash)
              i = i + 1
            end
          end
        end

        #If everything was deleted destroy the flag.
        if i == 0
          Rails.cache.delete("#{clazz}/#{mid_key}/Flag")
        #Else update the flag
        else
          flag = Rails.cache.read("#{clazz}/#{mid_key}/Flag")
          flag[:space] = (i - 1)
          #Sense we moved through every object and moved all the remaining objects down
          #there should be no empty spaces.
          flag[:empty] = -1
          Rails.cache.write("#{clazz}/#{mid_key}/Flag", flag)
        end
      end

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
      clazz = original_clazz
      while(clazz.respond_to? :destroy_array_cache)

        #AR - Clear all caches related to the old route_id
        clazz.destroy_array_cache(:route_id => self.try(:send, ("#{clazz.route_id}_was")).to_s)
        #AR - Clear all caches related to the new route_id just in case
        clazz.destroy_array_cache(:route_id => self.try(:send, ("#{clazz.route_id}")).to_s)
        #AR - If the new and old are the same All that will happen on the second call is that
        #it will write the flag out and then destroy it. A very tiny bit of work
        #for a great amount of extra protection.

        # AR - Remember to include models_in_index in your helper call in the corresponding index cache.
        clazz.destroy_array_cache(:obj => self)

        clazz = clazz.superclass
      end

      #AR - For Safety this will not recurse upwards for the extra cache maintenance
      extra_cache_maintenance(alive)

    end

    #Sense the current in_scope requires the object to be in the database, this has to be called in case the new version that has been 
    #saved fits into any cache's scope. The above call to clear index caches is basically the object_was call, while this is just the call 
    #for the update object.
    def post_cache_work
      original_clazz = self.class
      clazz = original_clazz

      while(clazz.respond_to? :destroy_array_cache)
        # AR - Remember to include models_in_index in your helper call in the corresponding index cache.
        clazz.destroy_array_cache(:obj => self)

        clazz = clazz.superclass
      end

    end

    #AR - For Safety this will not recurse upwards for the extra cache maintenance
    def extra_cache_maintenance alive
      method = (@_cache_extra_maintance || Proc.new{})
      method.call
    end

    def in_scope scope

      self.class.where(scope).exists?(self.id)

    end

  end
end