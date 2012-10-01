module FlagpoleSitta
  ##
  #A ‘hash’ in the cache which you can use to check for the existence of an object
  module ExistenceHash

    extend ActiveSupport::Concern

    included do
      before_save :existence_hash_save_update
      before_destroy :existence_hash_destory_update
    end

    module ClassMethods

       #Options :emptystack will make it generate a key for the emptystack instead of the general cache array.
      def eh_key_gen key, options={}

        superclazz = get_super_with_existence_hash

        end_key = end_key_gen key, options[:class]


        if options[:emptystack]
          "#{superclazz}/ExistenceHash/EmptyStack/#{end_key}"
        else
          "#{superclazz}/ExistenceHash/#{end_key}"
        end

      end

      def end_key_gen key, clazz
        if clazz
          "#{clazz}/#{key}"
        else
          "#{key}"
        end
      end


      #Creates the 'hash' in the cache.
      def initialize_existence_hash

        superclazz = get_super_with_existence_hash

        #Used to emulate an array, keeps the stored count and space. The space is not actually a count of existing entries, but rather how long
        #the 'container' goes, it starts at 0, so thats why 1 is subtracted. The count is well the count. They should start out the same. 
        count = superclazz.count

        flag = {:space => (count - 1), :count => count, :empty => -1}

        flag_key = eh_key_gen "Flag"
        FlagpoleSitta::CommonFs.flagpole_cache_write(flag_key, flag)
        i = 0
        superclazz.find_each do |m|
          #Route ID is the key. The POS is used to emulate an array, along with the length stored in the flag.
          main_key = eh_key_gen m.send(m.class.route_id), :class => m.class
          FlagpoleSitta::CommonFs.flagpole_cache_write(main_key, {:type => m.class.to_s, :pos => i, :num => m.has_attribute?('num') ? (m.num || 0) : 0})
          array_key = eh_key_gen i
          FlagpoleSitta::CommonFs.flagpole_cache_write(array_key, {:key => m.send(m.class.route_id).to_s, :type => m.class.to_s})
          i = i + 1
        end

        flag

      end

      #Gets a value from the 'hash' in the cache given a key.
      def get_existence_hash key

        clazz = self

        superclazz = get_super_with_existence_hash
        #Try to find the hash
        flag_key = eh_key_gen "Flag"
        flag = FlagpoleSitta::CommonFs.flagpole_cache_read(flag_key)
        #If it doesn't exist start the process of creating it
        if flag.nil?
          initialize_existence_hash
        end

        main_key = eh_key_gen key, :class => clazz
        FlagpoleSitta::CommonFs.flagpole_cache_read(main_key)

      end

      #Increments a value from the 'hash' in the cache given a key.
      def increment_existence_hash key

        clazz = self
          
        superclazz = get_super_with_existence_hash
        #Try to find the hash
        hash = get_existence_hash key

        #Update the hash key if it exists
        if hash
          hash[:num] = hash[:num] + 1
          main_key = eh_key_gen key, :class => clazz
          FlagpoleSitta::CommonFs.flagpole_cache_write(main_key, hash)
        end

        #Return the value
        hash

      end

      #Goes through each entry in the hash returning a key and value
      def each_existence_hash &block

        clazz = self

        superclazz = get_super_with_existence_hash

        flag_key = eh_key_gen "Flag"
        flag = FlagpoleSitta::CommonFs.flagpole_cache_read(flag_key)

        if flag.nil?
          flag = initialize_existence_hash
        end

        unless flag[:count] == 0
          for i in 0..flag[:space] do

            cur_array_key = eh_key_gen i
            value = FlagpoleSitta::CommonFs.flagpole_cache_read(cur_array_key)

            if value.present? && value[:type].to_s.eql?(clazz.to_s)
              cur_main_key = eh_key_gen value[:key], :class => value[:type]
              hash = FlagpoleSitta::CommonFs.flagpole_cache_read(cur_main_key)
              #This if statement is to make it fail gracefully if the cache has degraded.
              if hash.present?
                yield value[:key], hash
              end
            end

          end
        end

        nil

      end

      #Gets its original super class.
      def get_super_with_existence_hash

        if @_existence_hash_main_class.nil?

          c = self
          #Get the original super class that declares the existence hash

          while(c.superclass.respond_to? :get_existence_hash)
            c = c.superclass
          end

          @_existence_hash_main_class = c

        end

        @_existence_hash_main_class

      end

    end

    def existence_hash_save_update
      self.update_existence_hash(true)
    end

    def existence_hash_destory_update
      self.update_existence_hash(false)
    end

    #Updates the 'hash' on save of any of its records.
    def update_existence_hash alive

      begin
        #Get the Current Class and the Old Class in case the object changed classes.
        #If its the base object, ie type is nil, then return class as the old_clazz.
        #If the object doesn't have the type field assume it can't change classes.
        new_clazz = self.has_attribute?('type') ? (self.type || self.class.to_s) : self.class.to_s
        old_clazz = self.has_attribute?('type') ? (self.type_was || self.class.to_s) : self.class.to_s
        superclazz = self.class.get_super_with_existence_hash

        #Old key is where it was, and new is where it is going.
        new_key = new_clazz.respond_to?(:constantize) ? self.send("#{new_clazz.constantize.route_id}") : nil
        old_key = old_clazz.respond_to?(:constantize) ? self.send("#{old_clazz.constantize.route_id}_was") : nil

        new_main_key = superclazz.eh_key_gen new_key, :class => new_clazz
        old_main_key = superclazz.eh_key_gen old_key, :class => old_clazz

        flag_key = superclazz.eh_key_gen "Flag"
        flag = FlagpoleSitta::CommonFs.flagpole_cache_read(flag_key)

        if flag.nil?
          flag = self.class.initialize_existence_hash
        end
        
        #If its a new record add it to the 'hash'
        if self.new_record?
          flag[:count] = flag[:count] + 1
          #if there are empty containers use them
          if flag[:empty] > -1
            #Find any empty container to use by popping it off of the top of the "stack".
            empty_key = superclazz.eh_key_gen flag[:empty], :emptystack => true
            i = FlagpoleSitta::CommonFs.flagpole_cache_read(empty_key)
            #Sense its going to be used remove its reference from the Stack.
            FlagpoleSitta::CommonFs.flagpole_cache_delete(empty_key)
            #Update the empty on flag to now hit the newest none used container on the stack.
            flag[:empty] = flag[:empty] - 1
          #Else add a space to the end.
          else
            #AR - update the array's end point
            flag[:space] = flag[:space] + 1
            i = flag[:space]
          end
          hash = {:type => new_clazz, :num => self.has_attribute?('num') ? (self.num || 0) : 0, :pos => i}
        #If its an already existing record them get its existence hash, and then remove it from the cache.
        else
          hash = FlagpoleSitta::CommonFs.flagpole_cache_read(old_main_key)
          hash[:type] = new_clazz
        end

        array_main_key = superclazz.eh_key_gen hash[:pos]

        #Before new info gets written make sure to delete all the old records just in case. The New location before it gets used too.
        FlagpoleSitta::CommonFs.flagpole_cache_delete(new_main_key)
        FlagpoleSitta::CommonFs.flagpole_cache_delete(old_main_key)
        FlagpoleSitta::CommonFs.flagpole_cache_delete(array_main_key)

        #If the record is not being destroyed add new route_id to existence hash
        if alive
          FlagpoleSitta::CommonFs.flagpole_cache_write(new_main_key, hash)
          FlagpoleSitta::CommonFs.flagpole_cache_write(array_main_key, {:type => new_clazz, :key => new_key})
        else
          if hash[:pos] == flag[:space]
            flag[:space] = flag[:space] - 1
          else
            flag[:empty] = flag[:empty] + 1
            empty_key = superclazz.eh_key_gen flag[:empty], :emptystack => true
            FlagpoleSitta::CommonFs.flagpole_cache_write(empty_key, hash[:pos])
          end
          flag[:count] = flag[:count] - 1
        end

        FlagpoleSitta::CommonFs.flagpole_cache_write(flag_key, flag)
      rescue Exception => e  
        #Keep ending up with one of the array objects having a key of nil. Despite the fact that it would have to at least start with /view
        #becuase of the way its set up in the helper. If that happens all bets are off and just clear everything.
        Rails.cache.clear
        Rails.logger.error("EXISTANCE HASH FAILURE CACHE IS BEING NUKED :: FLAGPOLE_SITTA")
        Rails.logger.error(e.message)
        e.backtrace.each do |b|
          Rails.logger.error("\t" + b.to_s)
        end
        puts "EXISTANCE HASH FAILURE CACHE IS BEING NUKED :: FLAGPOLE_SITTA"
        puts e.message
        e.backtrace.each do |b|
            puts "\t" + b.to_s
        end
      end

    end

  end
end
