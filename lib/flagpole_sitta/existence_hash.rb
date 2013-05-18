module FlagpoleSitta
  ##
  #A ‘hash’ in the cache which you can use to check for the existence of an object,
  #along with its 'count' and last updated.
  #
  #The function of the count is for analytics, and the function of the last updated is to
  #be used with http caching.
  module ExistenceHash

    extend ActiveSupport::Concern

    included do
      after_destroy :after_destroy_update_existence_hash
      after_save :after_save_update_existence_hash
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

      def eh_key_gen

        if @_eh_key_gen.nil?

          key = "#{get_super_with_existence_hash}/ExistenceHash"

          @_eh_key_gen = FlagpoleSitta::CommonFs.flagpole_full_key(key)

        end

        @_eh_key_gen

      end

      def eh_lock_key_gen route_id
        "#{eh_key_gen}/#{route_id}/lock"
      end

      def master_existance_hash

        if @existance_hash.nil?
          @existance_hash = Redis::HashKey.new(eh_key_gen, :marshal => true)
        end

        @existance_hash

      end

      def existance_hash

        get_super_with_existence_hash.master_existance_hash

      end

      def interal_hash count, obj
        countent = (br_value_field ? obj.send(br_value_field) : nil)
        updated_at = (obj.respond_to?(:updated_at) ? obj.updated_at : nil)
        type = obj.has_attribute?('type') ? ((obj.type.present? ? obj.type : nil) || obj.class) : obj.class

        {
          :count => (count || 0), 
          :type => type, 
          :updated_at => updated_at,
          :content => countent,
          :id => obj.id
        }
      end

      #Gets a value from the 'hash' in the cache given a key.
      def get_existence_hash key, create_if_not_found = false

        hash = existance_hash[key]

        create = false

        if hash

          #Do nothing its fine

        else

          Redis::Mutex.with_lock(eh_lock_key_gen(key)) do

            if obj = self.where(route_id_field.to_sym => key).first
              hash = interal_hash(0,obj)
            elsif br_value_field && br_default_value && create_if_not_found
              create = true
            else
              hash = {:nil => true}
            end

            if hash
              existance_hash[key] = hash
            end

          end

        end

        if create 
          value = self.br_default_value
          obj = self.create(self.route_id_field.to_sym => key, self.br_value_field.to_sym => value)
          hash = existance_hash[key]
        end

        if hash && hash[:nil]
          nil
        else
          hash
        end

      end

      def [] key

        hash = get_existence_hash(key, true)

        value = hash ? hash[:content] : nil

        br_make_safe(value)

      end

      #Increments a value from the 'hash' in the cache given a key.
      def increment_existence_hash key
        get_existence_hash key
        Redis::Mutex.with_lock(eh_lock_key_gen(key)) do
          if (hash = existance_hash[key]) && hash[:count]
            hash[:count] += 1
            existance_hash[key] = hash
          end
        end
        get_existence_hash key
      end

      #Goes through each entry in the hash returning a key and value
      def each_existence_hash_count &block
        existance_hash.each do |key, hash|

          if hash[:count].present?
            yield key, hash[:count]
          end

        end

        nil

      end

      protected

      def br_value_field
        if @_br_value_field != false
          @_br_value_field ||= (self.superclass.respond_to?(:br_value_field) ? self.superclass.br_value_field : false)
        end
        @_br_value_field
      end
      
      #Will look up the object chain till it finds what it was set to, or not set too.
      def br_safe_content?
        if @_br_safe_content.nil? 
          @br_safe_content ||= (self.superclass.respond_to?(:br_safe_content) ? self.superclass.br_safe_content : false)
        end
        @_br_safe_content
      end

      #Will look up the object chain till it finds what it was set to, or not set too. 
      #Default value cannot be nil.
      def br_default_value
        if @_br_default_value != false
          @_br_default_value ||= (self.superclass.respond_to?(:br_default_value) ? self.superclass.br_default_value : false)
        end
        @_br_default_value
      end

      def br_make_safe value
        value = value.present? ? value : nil
        if self.br_safe_content? && value.respond_to?(:html_safe)
          value = value.html_safe
        end

        value
      end

    end

    protected

    def existance_hash
      self.class.existance_hash
    end


    def interal_hash count, obj
      self.class.interal_hash(count, obj)
    end

    def after_destroy_update_existence_hash
      Redis::Mutex.with_lock(self.class.eh_lock_key_gen(self.route_id_was)) do
        if !self.new_record?
          hash = existance_hash[self.route_id_was]
          if hash.nil? || self.id_was == hash[:id]
            existance_hash[self.route_id_was] = {:nil => true}
          end
        end
      end
    end

    #Updates the 'hash' on save of any of its records.
    def after_save_update_existence_hash
      Redis::Mutex.with_lock(self.class.eh_lock_key_gen(self.route_id_was)) do
        if !self.new_record?
          hash = existance_hash[self.route_id_was]
          if existance_hash[self.route_id_was].class.eql?(Hash) && self.id_was == hash[:id]
            @_eh_old_count = existance_hash[self.route_id_was][:count]
          end
          if hash.nil? || self.id_was == hash[:id]
            existance_hash[self.route_id_was] = {:nil => true}
          end
        end
      end
      Redis::Mutex.with_lock(self.class.eh_lock_key_gen(self.route_id)) do
        existance_hash[self.route_id] = interal_hash(@_eh_old_count, self)
      end
    end

  end
end