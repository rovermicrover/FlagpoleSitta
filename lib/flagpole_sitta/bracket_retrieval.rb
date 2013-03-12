module FlagpoleSitta
  ##
  #Used for getting and caching settings or html fragments stored in the database.
  module BracketRetrieval

    extend ActiveSupport::Concern

    included do
      before_save :br_get_state
      before_destroy :br_get_state
      after_commit :br_update
    end

    #After update destroy old cache and write new one.

    def br_get_state
      @_br_new_record = self.new_record?
      @_br_old_key = self.send(self.class.br_key_field.to_s + "_was")
    end

    def br_update
      if !@_br_new_record
        self.class.bracket_retrieval_hash.delete(@_br_old_key)
      end 
    end

    module ClassMethods

      def [] key

        value = bracket_retrieval_hash[key]

        #If its in cache return that, unless blank, then return nil.
        if value.nil?
          Redis::Mutex.with_lock(get_br_key + "/lock") do
            value = bracket_retrieval_hash[key]
            if value.nil?
              #If the object is in the database put it into the cache then return it.
              if obj = self.send("find_by_#{self.br_key_field}", key)
                value = obj.send(self.br_value_field)
                bracket_retrieval_hash[key] = value
              #Else create the corresponding object with the default value.
              else
                value = self.br_default_value
                rec = self.create(self.br_key_field.to_sym => key, self.br_value_field.to_sym => value)
                bracket_retrieval_hash[key] = rec.send(self.br_value_field)
              end
            end
          end
        end

        value = br_make_safe value

      end

      def bracket_retrieval_hash
        if @bracket_retrieval_hash.nil?
          @bracket_retrieval_hash = Redis::HashKey.new(get_br_key, :marshal => true)
        end

        @bracket_retrieval_hash
      end

      def get_br_key
        if @_br_key.nil?

          key = "#{self}/BracketRetrieval"

          @_br_key = FlagpoleSitta::CommonFs.flagpole_full_key(key)
        end

        @_br_key

      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def br_safe_content?
        if @_br_safe_content.nil? 
          @br_safe_content = (self.superclass.respond_to?(:br_safe_content) ? self.superclass.br_safe_content : false)
        end
          
        @_br_safe_content
      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def br_key_field
        @_br_key_field ||= (self.superclass.respond_to?(:br_key_field) ? self.superclass.br_key_field : :name)
      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def br_value_field
        @_br_value_field ||= (self.superclass.respond_to?(:br_value_field) ? self.superclass.br_value_field : :content)
      end

      #Will look up the object chain till it finds what it was set to, or not set too. 
      #Default value cannot be nil.
      def br_default_value
        @_br_default_value ||= (self.superclass.respond_to?(:br_default_value) ? self.superclass.br_default_value : "")
      end

      def br_make_safe value
        #Return nil if its not present.
        #Make the buffer html_safe only if flag is set.
        value = value.present? ? value : nil
        if self.br_safe_content? && value.respond_to?(:html_safe)
          value = value.html_safe
        end

        value
      end

    end

  end
end