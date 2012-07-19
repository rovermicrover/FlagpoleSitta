module FlagpoleSitta
  module BracketRetrieval

    extend ActiveSupport::Concern

    #When forcing a call back into a class from a module you must do it inside an include block
    included do
      validates_uniqueness_of (@_key_field || "name").to_sym
      validates_presence_of (@_key_field || "name").to_sym
      before_save :br_update_save
      before_destroy :br_update_destroy
    end

    def br_update_save
      self.br_update(true)
    end

    def br_update_destroy
      self.br_update(false)
    end

    def br_update alive
      downcased = self.class.name.downcase
      #Checks to make sure Controller Caching is on
      if Rails.application.config.action_controller.perform_caching
        Rails.cache.delete("#{downcased}/#{self.send(self.class.key_field + "_was")}")
        Rails.cache.write("#{downcased}/#{self.send(self.class.key_field)}", self.send(self.class.value_field))
      end
    end

    module ClassMethods

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
      def default_value
        result = @_default_value || (self.superclass.respond_to?(:default_value) ? self.superclass.default_value : nil) || ""
      end

      def [] key 
        downcased = self.to_s.downcase
        #If its in cache return that, unless blank, then return nil
        #elsif the object is in the database put it into the cache
        #then return it.
        #else create the corresponding object as blank, and return nil.
        #The last line there is why this extension should never be used
        #with user generated content.
        if value = Rails.cache.read("#{downcased}/#{key}") || Rails.cache.exist?("#{downcased}/#{key}")
          if value.present?
            value = self.safe_content? ? value.html_safe : value
          else
            #Always return nil even if the return value is blank.
            #Also if its blank we don't want to try to create it again
            #thus the reason for this odd nested if statement.
            value = nil
          end
        elsif obj = self.send("find_by_#{self.key_field}", key)
          value = obj.send(self.value_field)
          Rails.cache.write("#{downcased}/#{key}", value)
          value = value && self.safe_content? ? value.html_safe : value
        else
          rec = self.create(self.key_field.to_sym => key, self.value_field.to_sym => self.default_value)
          Rails.cache.write("#{downcased}/#{key}", rec.send(self.value_field))
          value = nil
        end
        value
      end
    end

  end
end