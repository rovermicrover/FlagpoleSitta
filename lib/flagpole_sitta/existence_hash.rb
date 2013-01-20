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
      def eh_key_gen

        key = "#{@superclazz}/ExistenceHash"

        key = FlagpoleSitta::CommonFs.flagpole_full_key(key)

      end

      def ch_key_gen

        key = "#{@superclazz}/CounterHash"

        key = FlagpoleSitta::CommonFs.flagpole_full_key(key)

      end

      def ex_ch_init_check_key_gen

        key = "#{@superclazz}/InitCheck"

        key = FlagpoleSitta::CommonFs.flagpole_full_key(key)

      end

      def existance_hash
        @existance_hash
      end

      def counter_hash
        @counter_hash
      end


      #Creates the 'hash' in the cache.

      def initialize_c_a_hashes
        if !@counter_hash || !@existance_hash || !@initcheck || !@initcheck.value

          get_super_with_existence_hash

          flag_key_ch = ch_key_gen
          flag_key_eh = eh_key_gen
          flag_key_init = ex_ch_init_check_key_gen

          @counter_hash = Redis::HashKey.new(flag_key_ch, :marshal => true)
          @existance_hash = Redis::HashKey.new(flag_key_eh, :marshal => true)

          @superclazz.find_each do |m|
            @counter_hash[m.send(m.class.route_id)] = m.has_attribute?('num') ? (m.num.to_i || 0) : 0
            @existance_hash[m.send(m.class.route_id)] = m.class
          end

          @initcheck = Redis::Value.new(flag_key_init)
          @initcheck.value = true

        end

        nil

      end

      #Gets a value from the 'hash' in the cache given a key.
      def get_existence_hash key
        initialize_c_a_hashes

        puts @existance_hash.to_a
        puts @counter_hash.to_a

        if (type = @existance_hash[key]) && (num = @counter_hash[key])
          {:type => type, :num => num}
        else
          nil
        end

      end

      #Increments a value from the 'hash' in the cache given a key.
      def increment_existence_hash key
        initialize_c_a_hashes

        puts @existance_hash.to_a
        puts @counter_hash.to_a

        if (result = get_existence_hash key)
          @counter_hash.incr(key)
          result
        else
          nil
        end

      end

      #Goes through each entry in the hash returning a key and value
      def each_existence_hash &block
        initialize_c_a_hashes

        @existance_hash.each do |key, type|

          if type.present? && type.eql?(clazz)
            cur = get_existence_hash key
            yield cur
          end

        end

        nil

      end

      #Gets its original super class.
      def get_super_with_existence_hash

        if @superclazz.nil?

          c = self
          #Get the original super class that declares the existence hash

          while(c.superclass.respond_to? :get_existence_hash)
            c = c.superclass
          end

          @superclazz = c

        end

        @superclazz

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
      self.class.initialize_c_a_hashes
      #Get the Current Class and the Old Class in case the object changed classes.
      #If its the base object, ie type is nil, then return class as the old_clazz.
      #If the object doesn't have the type field assume it can't change classes.
      new_clazz = self.has_attribute?('type') ? (self.type || self.class) : self.class
      old_clazz = self.has_attribute?('type') ? (self.type_was || self.class) : self.class

      if new_clazz.class.eql?(String)
        new_clazz = new_clazz.constantize
      end

      if old_clazz.class.eql?(String)
        old_clazz = old_clazz.constantize
      end

      puts self.class.existance_hash
      puts self.class.counter_hash

      #Old key is where it was, and new is where it is going.
      new_key = self.send("#{new_clazz.route_id}")
      old_key = self.send("#{old_clazz.route_id}_was")
      
      #If its a new record and its alive add it to the 'hash'
      if self.new_record? && alive

        self.class.existance_hash[new_key] = self.class
        self.class.counter_hash[new_key] = 0

      #Else move forward unless its a new record that is not alive
      elsif !self.new_record?

        #If the record is dying just remove it
        if !alive
          self.class.existance_hash.delete(old_key)
          self.class.counter_hash.delete(old_key)
        #Else If everything has changed nil out the old keys
        #and place info in new keys.
        elsif !new_key.eql?(old_key)
          self.class.existance_hash.delete(old_key)
          num = self.class.counter_hash[old_key]
          self.class.counter_hash.delete(old_key)

          self.class.existance_hash[new_key] = new_clazz
          self.class.counter_hash[new_key] = num
        #Else if the keys are the same but the class is different update the class.
        elsif !new_clazz.eql?(old_clazz)
          self.class.existance_hash[old_key] = new_clazz
        end

      end

    end

  end
end
