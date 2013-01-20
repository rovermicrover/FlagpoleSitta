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

      clazz = self.class

      key = clazz.get_br_key(self.send(self.class.key_field + "_was"))

      FlagpoleSitta::CommonFs.flagpole_cache_delete(key)

      if alive
        key = clazz.get_br_key(self.send(self.class.key_field))
        value = self.send(self.class.value_field)
        FlagpoleSitta::CommonFs.flagpole_cache_write(key, value)
      end
      
    end

    module ClassMethods

      def get_br_key key

        clazz = self

        "#{clazz}/BracketRetrieval/#{key}"

      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def safe_content?
        result = @_safe_content || (self.superclass.respond_to?(:safe_content?) ? self.superclass.safe_content? : nil) || false
      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def key_field
        result = @_key_field || (self.superclass.respond_to?(:key_field) ? self.superclass.key_field : nil) || "name"
      end

      #Will look up the object chain till it finds what it was set to, or not set too.
      def value_field
        result = @_value_field || (self.superclass.respond_to?(:value_field) ? self.superclass.value_field : nil) || "content"
      end

      #Will look up the object chain till it finds what it was set to, or not set too. 
      #Default value cannot be nil.
      def default_value
        result = @_default_value || (self.superclass.respond_to?(:default_value) ? self.superclass.default_value : nil) || ""
      end

      def [] key 
        clazz = self
        #If its in cache return that, unless blank, then return nil.
        if value = FlagpoleSitta::CommonFs.flagpole_cache_read(get_br_key(key)) || FlagpoleSitta::CommonFs.flagpole_cache_exist?(get_br_key(key))
          if value.present?
            value = self.safe_content? ? value.html_safe : value
          else
            #Always return nil even if the return value is blank.
            #Also if its blank we don't want to try to create it again
            #thus the reason for this odd nested if statement.
            value = nil
          end
        #Else if the object is in the database put it into the cache then return it.
        elsif obj = self.send("find_by_#{self.key_field}", key)
          value = obj.send(self.value_field)
          FlagpoleSitta::CommonFs.flagpole_cache_write(get_br_key(key), value)
          value = value && self.safe_content? ? value.html_safe : value
        #Else create the corresponding object as blank, and return nil.
        #The last line there is why this extension should never be used with user generated content.
        else
          rec = self.create(self.key_field.to_sym => key, self.value_field.to_sym => self.default_value)
          FlagpoleSitta::CommonFs.flagpole_cache_write(get_br_key(key), rec.send(self.value_field))
          value = nil
        end
        value
      end
    end

  end
end