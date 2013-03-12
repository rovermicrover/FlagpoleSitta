module FlagpoleSitta
  ##
  #A ‘hash’ in the cache which you can use to check for the existence of an object
  module ExistenceHash

    extend ActiveSupport::Concern

    included do
      before_save :eh_update_save
      before_destroy :eh_update_destory
      after_commit :update_existence_hash
    end

    module ClassMethods

      #Gets its original super class.
      def get_super_with_existence_hash

        if @superklass.nil?

          c = self
          #Get the original super class that declares the existence hash

          while(c.superclass.respond_to? :get_existence_hash)
            c = c.superclass
          end

          @superklass = c

        end

        @superklass

      end

      #Options :emptystack will make it generate a key for the emptystack instead of the general cache array.
      def eh_key_gen
        if @_eh_key_gen.nil?

          get_super_with_existence_hash

          key = "#{@superklass}/ExistenceHash"

          @_eh_key_gen = FlagpoleSitta::CommonFs.flagpole_full_key(key)

        end

        @_eh_key_gen

      end

      def ch_key_gen

        if @_ch_key_gen.nil?

          get_super_with_existence_hash

          key = "#{@superklass}/CounterHash"

          @_ch_key_gen = FlagpoleSitta::CommonFs.flagpole_full_key(key)
        end

        @_ch_key_gen

      end

      def ex_ch_init_check_key_gen

        if @_ex_ch_init_check_key_gen.nil?

          get_super_with_existence_hash

          key = "#{@superklass}/InitCheck"

          @_ex_ch_init_check_key_gen = FlagpoleSitta::CommonFs.flagpole_full_key(key)

        end

        @_ex_ch_init_check_key_gen

      end

      def existance_hash
        if @existance_hash.nil?
          @existance_hash = Redis::HashKey.new(eh_key_gen, :marshal => true)
        end

        @existance_hash

      end

      def counter_hash
        if @counter_hash.nil?
          @counter_hash = Redis::HashKey.new(ch_key_gen, :marshal => true)
        end

        @counter_hash

      end

      def initcheck
        if @initcheck.nil?
          @initcheck = Redis::Value.new(ex_ch_init_check_key_gen, :marshal => true)
        end

        @initcheck
      end


      #Creates the 'hash' in the cache.

      def initialize_c_a_hashes
        if !initcheck.value

          Redis::Mutex.with_lock(ch_key_gen + "/lock") do
            if !initcheck.value

              if counter_hash.empty? || existance_hash.empty?

                get_super_with_existence_hash.find_each do |m|
                  counter_hash[m.route_id] = 0
                  existance_hash[m.route_id] = m.class
                end

              end

              initcheck_set(true)
            end
          end

        end

        nil

      end

      #Gets a value from the 'hash' in the cache given a key.
      def get_existence_hash key
        initialize_c_a_hashes
        if (type = existance_hash[key]) && (num = counter_hash[key])
          {:type => type, :num => num.to_i}
        else
          nil
        end

      end

      #Increments a value from the 'hash' in the cache given a key.
      def increment_existence_hash key
        initialize_c_a_hashes

        if (result = get_existence_hash key)
          counter_hash.incr(key)
        end

        result

      end

      #Goes through each entry in the hash returning a key and value
      def each_existence_hash &block
        initialize_c_a_hashes

        existance_hash.each do |key, type|

          if type.present? && type.eql?(self)
            cur = get_existence_hash key
            yield key, cur
          end

        end

        nil

      end

      protected

      def initcheck_set value

        @initcheck.value = value

      end

    end

    protected
    def eh_update_save
      @_eh_alive = true
      fs_get_state
    end

    def eh_update_destory
      @_eh_alive = false
      fs_get_state
    end

    #Updates the 'hash' on save of any of its records.
    def update_existence_hash
      self_was = @_fs_old_state
      self_cur = self

      #Get the Current Class and the Old Class in case the object changed classes.
      #If its the base object, ie type is nil, then return class as the old_klass.
      #If the object doesn't have the type field assume it can't change classes.
      if self_was
        old_klass = self_was.class
        if old_klass.class.eql?(String)
          old_klass = old_klass.constantize
        end
        old_klass.initialize_c_a_hashes
        old_key = self_was.route_id_was
      end

      if @_eh_alive
        new_klass = self_cur.has_attribute?('type') ? ((self_cur.type.present? ? self_cur.type : nil) || self_cur.class) : self_cur.class
        if new_klass.class.eql?(String)
          new_klass = new_klass.constantize
        end
        new_klass.initialize_c_a_hashes
        new_key = self_cur.route_id
      end
      
      #If its a new record and its alive add it to the 'hash'
      if self_was.nil? && @_eh_alive

        new_klass.existance_hash[new_key] = self_cur.class
        new_klass.counter_hash[new_key] = 0

      #Else move forward unless its a new record that is not alive
      elsif self_was

        #If the record is dying just remove it
        if !@_eh_alive
          old_klass.existance_hash.delete(old_key)
          old_klass.counter_hash.delete(old_key)
        #Else If everything has changed nil out the old keys
        #and place info in new keys.
        elsif !new_key.eql?(old_key) || !new_klass.eql?(old_klass)
          old_klass.existance_hash.delete(old_key)
          num = old_klass.counter_hash[old_key]
          old_klass.counter_hash.delete(old_key)

          new_klass.existance_hash[new_key] = new_klass
          new_klass.counter_hash[new_key] = num
        end

      end

    end

  end
end
