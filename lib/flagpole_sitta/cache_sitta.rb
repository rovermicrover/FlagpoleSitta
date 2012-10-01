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

      def clazz
        self
      end

      #Determines if its for an index array or show array.
      def mid_key_gen route_id
        if route_id
          mid_key = "#{route_id}/ShowArray"
        else
          mid_key = "IndexArray"
        end
      end

      #Options :emptystack will make it generate a key for the emptystack instead of the general cache array.
      def array_cache_key_gen key, route_id, options={}

        mid_key = mid_key_gen route_id

        model = options[:model] || clazz


        if options[:emptystack]
          "#{model}/#{mid_key}/EmptyStack/#{key}"
        else
          "#{model}/#{mid_key}/#{key}"
        end

      end

      #Creates the 'array' in the cache.
      def initialize_array_cache route_id = nil

        flag_key = array_cache_key_gen "Flag", route_id

        flag = {:space => -1, :empty => -1}

        FlagpoleSitta::CommonFs.flagpole_cache_write(flag_key, flag)

        flag

      end

      #Updates the 'array' in the cache.
      #Options :route_id which determines the type of mid_key
      def update_array_cache key, options={}

        flag_key = array_cache_key_gen "Flag", options[:route_id]

        flag = FlagpoleSitta::CommonFs.flagpole_cache_read(flag_key)

        #AR - If it doesn't exist start the process of creating it
        if flag.nil?
          flag = initialize_array_cache options[:route_id]
        end

        if flag[:empty] > -1
          #Find any empty container to use by popping it off of the top of the "stack".
          empty_key = array_cache_key_gen flag[:empty], options[:route_id], :emptystack => true

          i = FlagpoleSitta::CommonFs.flagpole_cache_read(empty_key)
          #Sense its going to be used remove its reference from the Stack.
          FlagpoleSitta::CommonFs.flagpole_cache_delete(empty_key)
          #Update the empty on flag to now hit the newest none used container on the stack.
          flag[:empty] = flag[:empty] - 1
        else
          #AR - update the array's end point
          flag[:space] = flag[:space] + 1
          i = flag[:space]
        end
       
        #AR - write out the new index at the end of the array
        array_key = array_cache_key_gen i, options[:route_id]
        FlagpoleSitta::CommonFs.flagpole_cache_write(array_key, {:key => key, :scope => options[:scope]})

        #AR - update flag in the cache
        flag_key = array_cache_key_gen "Flag", options[:route_id]
        FlagpoleSitta::CommonFs.flagpole_cache_write(flag_key, flag)

        array_key

      end

      #Loops through the array in the cache.
      def each_cache route_id = nil, &block

        flag_key = array_cache_key_gen "Flag", route_id

        flag = FlagpoleSitta::CommonFs.flagpole_cache_read(flag_key)

        #AR - If there aren't any index do nothing.
        #Else wise loop through every index.
        #If it actually does exist then yield.
        if flag
          for i in 0..flag[:space] do
            array_key = array_cache_key_gen i, route_id
            hash = FlagpoleSitta::CommonFs.flagpole_cache_read(array_key)
            yield hash
          end
        end

        nil

      end

      #Nukes all corresponding caches for a given array.
      def destroy_array_cache options={}

        each_cache options[:route_id] do |hash|
          #A Check in Case there is some type of cache failure, or it is an empty spot, also if it has no scope, or it falls in scope
          if hash.present? && (hash[:scope].nil? || options[:obj].in_scope(hash[:scope]))
            #Get all the associated.
            associated = FlagpoleSitta::CommonFs.flagpole_cache_read(hash[:key])[:associated]
            Rails.logger.info "#{hash[:key]} is being cleared"
            #Destroy the actually cache
            FlagpoleSitta::CommonFs.flagpole_cache_delete(hash[:key])
            #The associated objects will always include the object we got the actually cache from
            associated.each do |a|
              #Get the base key
              base_key = a.gsub(/\/[^\/]*\z/, "")
              #Get the flag. Capture the god damn flag!
              flag_key = base_key + "/Flag"
              #Get its location in the 'Array'
              n = a.split("/").last
              # Check in case of cache failure
              if flag = FlagpoleSitta::CommonFs.flagpole_cache_read(flag_key)
                #Add an empty spot to the 'Array'
                flag[:empty] = flag[:empty] + 1
                empty_stack_key = base_key + "/EmptyStack/" + flag[:empty].to_s
                #Save the empty spot location to the 'Stack'
                FlagpoleSitta::CommonFs.flagpole_cache_write(empty_stack_key, n)
                #Update the flag
                FlagpoleSitta::CommonFs.flagpole_cache_write(flag_key, flag)
              end

              #Finally get rid of the associated cache object.
              FlagpoleSitta::CommonFs.flagpole_cache_delete(a)
            end
          #Else It is not in scope so the cache lives to fight another day!
          end
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
      begin
        original_clazz = self.class
        # Also have to go through all its super objects till the super objects aren't cache sittaed
        # this is because the new updated object for a sub class, could have also been in a cache for
        # said sub class, but also in a cache for its super.
        cur_clazz = original_clazz
        while(cur_clazz.respond_to? :destroy_array_cache)

          #AR - Clear all caches related to the old route_id
          cur_clazz.destroy_array_cache(:route_id => self.try(:send, ("#{cur_clazz.route_id}_was")).to_s)
          #AR - Clear all caches related to the new route_id just in case
          cur_clazz.destroy_array_cache(:route_id => self.try(:send, ("#{cur_clazz.route_id}")).to_s)
          #AR - If the new and old are the same All that will happen on the second call is that
          #it will write the flag out and then destroy it. A very tiny bit of work
          #for a great amount of extra protection.

          # AR - Remember to include models_in_index in your helper call in the corresponding index cache.
          cur_clazz.destroy_array_cache(:obj => self)

          cur_clazz = cur_clazz.superclass
        end

        #AR - For Safety this will not recurse upwards for the extra cache maintenance
        extra_cache_maintenance(alive)
      rescue Exception => e  
        #Keep ending up with one of the array objects having a key of nil. Despite the fact that it would have to at least start with /view
        #becuase of the way its set up in the helper. If that happens all bets are off and just clear everything.
        Rails.cache.clear
        Rails.logger.error("CACHE FAILURE @BEFORE STATE CHANGE CACHE IS BEING NUKED :: FLAGPOLE_SITTA")
        Rails.logger.error(e.message)
        e.backtrace.each do |b|
          Rails.logger.error("\t" + b.to_s)
        end
        puts "CACHE FAILURE @BEFORE STATE CHANGE CACHE IS BEING NUKED :: FLAGPOLE_SITTA"
        puts e.message
        e.backtrace.each do |b|
            puts "\t" + b.to_s
        end
      end

    end

    #Sense the current in_scope requires the object to be in the database, this has to be called in case the new version that has been 
    #saved fits into any cache's scope. The above call to clear index caches is basically the object_was call, while this is just the call 
    #for the update object.
    def post_cache_work
      begin
        original_clazz = self.class
        cur_clazz = original_clazz

        while(cur_clazz.respond_to? :destroy_array_cache)
          # AR - Remember to include models_in_index in your helper call in the corresponding index cache.
          cur_clazz.destroy_array_cache(:obj => self)

          cur_clazz = cur_clazz.superclass
        end
      rescue Exception => e  
        #Keep ending up with one of the array objects having a key of nil. Despite the fact that it would have to at least start with /view
        #becuase of the way its set up in the helper. If that happens all bets are off and just clear everything.
        Rails.cache.clear
        Rails.logger.error("CACHE FAILURE @AFTER_SAVE CACHE IS BEING NUKED :: FLAGPOLE_SITTA")
        Rails.logger.error(e.message)
        e.backtrace.each do |b|
          Rails.logger.error("\t" + b.to_s)
        end
        puts "CACHE FAILURE @AFTER_SAVE CACHE IS BEING NUKED :: FLAGPOLE_SITTA"
        puts e.message
        e.backtrace.each do |b|
            puts "\t" + b.to_s
        end
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