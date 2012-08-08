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

      #Creates the 'hash' in the cache.
      def initialize_existence_hash

        superclazz = get_super_with_existence_hash

        #Used to emulate an array, keeps the stored count and space. The space is not actually a count of existing entries, but rather how long
        #the 'container' goes, it starts at 0, so thats why 1 is subtracted. The count is well the count. They should start out the same. 
        count = superclazz.count

        flag = {:space => (count - 1), :count => count, :empty => -1}

        Rails.cache.write("#{superclazz}/ExistenceHash/Flag", flag)
        i = 0
        superclazz.find_each do |m|
          #Route ID is the key. The POS is used to emulate an array, along with the length stored in the flag.
          Rails.cache.write("#{superclazz}/ExistenceHash/#{m.class}/#{m.send(m.class.route_id).to_s}", {:type => m.has_attribute?('type') ? m.type : m.class, :pos => i, :num => m.has_attribute?('num') ? m.num : 0})
          Rails.cache.write("#{superclazz}/ExistenceHash/#{i}", {:key => m.send(m.class.route_id).to_s, :type => m.class})
          i = i + 1
        end

        flag

      end

      #Gets a value from the 'hash' in the cache given a key.
      def get_existence_hash key

        clazz = self

        superclazz = get_super_with_existence_hash
        #Try to find the hash
        flag = Rails.cache.read("#{superclazz}/ExistenceHash/Flag")
        #If it doesn't exist start the process of creating it
        if flag.nil?
          initialize_existence_hash
        end

        Rails.cache.read("#{superclazz}/ExistenceHash/#{clazz}/#{key}")

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
          Rails.cache.write("#{superclazz}/ExistenceHash/#{clazz}/#{key}", hash)
        end

        #Return the value
        hash

      end

      #Goes through each entry in the hash returning a key and value
      def each_existence_hash &block

        clazz = self

        superclazz = get_super_with_existence_hash

        flag = Rails.cache.read("#{superclazz}/ExistenceHash/Flag")

        if flag.nil?
          flag = initialize_existence_hash
        end

        unless flag[:count] == 0
          for i in 0..flag[:space] do

            value = Rails.cache.read("#{superclazz}/ExistenceHash/#{i}")

            if value.present? && value[:type].eql?(clazz)
              hash = Rails.cache.read("#{superclazz}/ExistenceHash/#{value[:type]}/#{value[:key]}")
              yield value[:key], hash
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
      #Get the Current Class and the Old Class in case the object changed classes.
      #If its the base object, ie type is nil, then return class as the old_clazz.
      #If the object doesn't have the type field assume it can't change classes.
      new_clazz = self.has_attribute?('type') ? (self.type || self.class) : self.class
      old_clazz = self.has_attribute?('type') ? (self.type_was || self.class) : self.class
      superclazz = self.class.get_super_with_existence_hash

      #Old key is where it was, and new is where it is going.
      old_key = self.send("#{self.class.route_id}_was")
      new_key = self.send("#{self.class.route_id}")

      flag = Rails.cache.read("#{superclazz}/ExistenceHash/Flag")

      if flag.nil?
        flag = self.class.initialize_existence_hash
      end
      
      #If its a new record add it to the 'hash'
      if self.new_record?
        flag[:count] = flag[:count] + 1
        #if there are empty containers use them
        if flag[:empty] > -1
          #Find any empty container to use by popping it off of the top of the "stack".
          i = Rails.cache.read("#{superclazz}/ExistenceHash/EmptyStack/#{flag[:empty]}")
          #Sense its going to be used remove its reference from the Stack.
          Rails.cache.delete("#{superclazz}/ExistenceHash/EmptyStack/#{flag[:empty]}")
          #Update the empty on flag to now hit the newest none used container on the stack.
          flag[:empty] = flag[:empty] - 1
        #Else add a space to the end.
        else
          #AR - update the array's end point
          flag[:space] = flag[:space] + 1
          i = flag[:space]
        end
        hash = {:type => self.has_attribute?('type') ? self.type : self.class, :num => self.has_attribute?('num') ? self.num : 0, :pos => i}
      #If its an already existing record them get its existence hash, and then remove it from the cache.
      else
        hash = self.class.get_existence_hash(self.send("#{self.class.route_id}_was"))
        hash[:type] = new_clazz
        Rails.cache.delete("#{superclazz}/ExistenceHash/#{old_clazz}/#{old_key}")
      end

      #If the record is not being destroyed add new route_id to existence hash
      if alive
        Rails.cache.write("#{superclazz}/ExistenceHash/#{new_clazz}/#{new_key}", hash)
        Rails.cache.write("#{superclazz}/ExistenceHash/#{hash[:pos]}", {:key => new_key, :type => new_clazz})
      #The following check is needed if for some reason someone does destroy on a none saved record.
      elsif !self.new_record?
        if hash[:pos] == flag[:space]
          flag[:space] = flag[:space] - 1
        else
          flag[:empty] = flag[:empty] + 1
          Rails.cache.write("#{superclazz}/ExistenceHash/EmptyStack/#{flag[:empty]}", hash[:pos])
        end
        flag[:count] = flag[:count] - 1
        Rails.cache.delete("#{superclazz}/ExistenceHash/#{hash[:pos]}")
      end

      Rails.cache.write("#{superclazz}/ExistenceHash/Flag", flag)

    end

  end
end
