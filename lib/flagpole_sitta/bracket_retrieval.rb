module FlagpoleSitta
  ##
  #Used for getting and caching settings or html fragments stored in the database.
  module BracketRetrieval

    extend ActiveSupport::Concern

    included do
      validates_uniqueness_of (@_key_field || "key").to_sym
      validates_presence_of (@_key_field || "key").to_sym
      before_save :br_update_save
      before_destroy :br_update_destroy
    end

    def br_update_save
      self.br_update(true)
    end

    def br_update_destroy
      self.br_update(false)
    end

    #After update destroy old cache and write new one.
    def br_update alive

      self.class.initialize_bracket_retrieval_hash

      key = self.class.key_field + "_was"

      bracket_retrieval_hash = self.class.instance_variable_get(:@bracket_retrieval_hash)

      bracket_retrieval_hash.delete(key)

      if alive
        key = self.send(self.class.key_field)
        value = self.send(self.class.value_field)
        bracket_retrieval_hash[key] = value
      end
      
    end

    module ClassMethods

      def clazz

        self

      end

      def initialize_bracket_retrieval_hash
        if !@bracket_retrieval_hash
          @bracket_retrieval_hash = Redis::HashKey.new(get_br_key, :marshal => true)
        else
          @bracket_retrieval_hash
        end
      end

      def get_br_key

        "#{clazz}/BracketRetrieval"

      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def safe_content?
        if @_br_safe_content.nil? 
          @_br_safe_content = (self.superclass.respond_to?(:safe_content) ? self.superclass.safe_content : false)
        else
          @_br_safe_content
        end
      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def key_field
        @_br_key_field ||= (self.superclass.respond_to?(:key_field) ? self.superclass.key_field : "name")
      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def value_field
        @_br_value_field ||= (self.superclass.respond_to?(:value_field) ? self.superclass.value_field : "content")
      end

      #Will look up the object chain till it finds what it was set to, or not set too. 
      #Default value cannot be nil.
      def default_value
        @_br_default_value ||= (self.superclass.respond_to?(:default_value) ? self.superclass.default_value : "")
      end

      def make_safe value
        value = value.present? ? value : nil
        if self.safe_content? && value.respond_to?(:html_safe)
          value = value.html_safe
        end

        value
      end

      def [] key 
        initialize_bracket_retrieval_hash

        #If its in cache return that, unless blank, then return nil.
        if value = @bracket_retrieval_hash[key]
          #Do nothing object is good to go
        #Else if the object is in the database put it into the cache then return it.
        elsif obj = self.send("find_by_#{self.key_field}", key)
          value = obj.send(self.value_field)
          @bracket_retrieval_hash[key] = value
          value = make_safe value
        #Else create the corresponding object as blank, and return the default value.
        #The last line there is why this extension should never be used with user generated content.
        #But return nil if its not present.
        else
          value = self.default_value
          rec = self.create(self.key_field.to_sym => key, self.value_field.to_sym => value)
          @bracket_retrieval_hash[key] = rec.send(self.value_field)
        end

        value = make_safe value

      end

    end

  end
end