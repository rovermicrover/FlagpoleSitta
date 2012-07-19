module FlagpoleSitta
  module ExistenceHash

    extend ActiveSupport::Concern

    included do
      before_save :existence_hash_save_update
      before_destroy :existence_hash_destory_update
    end

    module ClassMethods

      def get_existence_hash key

        dcname = get_super_with_existence_hash.name.downcase
        #Try to find the hash
        flag = Rails.cache.read("#{dcname}_existence_hash_flag")
        #If it doesn't exist start the process of creating it
        if flag.nil?
          initialize_existence_hash
        end

        Rails.cache.read("#{dcname}_existence_hash/#{key}")

      end

      def increment_existence_hash key
          
        dcname = get_super_with_existence_hash.name.downcase
        #Try to find the hash
        hash = get_existence_hash key

        #Update the hash key if it exists
        if hash
          hash[:num] = hash[:num] + 1
          Rails.cache.write("#{dcname}_existence_hash/#{key}", hash)
        end

        #Return the value
        hash

      end

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

      def initialize_existence_hash

        c = get_super_with_existence_hash

        dcname = c.name.downcase

        #Used to emulate an array, keeps the stored count and space. The space is not actually a count of existing entries, but rather how long
        #the 'container' goes, it starts at 0, so thats why 1 is subtracted. The count is well the count. They should start out the same. 
        count = c.count

        flag = {:space => (count - 1), :count => count}

        Rails.cache.write("#{dcname}_existence_hash_flag", flag)
        i = 0
        c.find_each do |m|
          #Route ID is the key. The POS is used to emulate an array, along with the length stored in the flag.
          Rails.cache.write("#{dcname}_existence_hash/#{m.send(c.route_id).to_s}", {:type => m.has_attribute?('type') ? m.type : m.class, :pos => i, :num => 0})
          Rails.cache.write("#{dcname}_existence_hash/#{i}", {:key => m.send(c.route_id).to_s})
          i = i + 1
        end

        flag

      end

      def each_existence_hash &block

        dcname = get_super_with_existence_hash.name.downcase

        flag = Rails.cache.read("#{dcname}_existence_hash_flag")

        if flag.nil?
          flag = initialize_existence_hash
        end

        unless flag[:count] == 0
          for i in 0..flag[:space] do

            value = Rails.cache.read("#{dcname}_existence_hash/#{i}")

            if value.present?
              hash = Rails.cache.read("#{dcname}_existence_hash/#{value[:key]}")
              yield value[:key], hash
            end

          end
        end

        nil

      end

    end

    def existence_hash_save_update
      self.update_existence_hash(true)
    end

    def existence_hash_destory_update
      self.update_existence_hash(false)
    end

    def update_existence_hash alive
      c = self.class.get_super_with_existence_hash
      dcname = c.name.downcase

      #Old key is where it was, and new is where it is going.
      old_key = self.send("#{self.class.route_id}_was")
      new_key = self.send("#{self.class.route_id}")

      flag = Rails.cache.read("#{dcname}_existence_hash_flag")

      #If it had a route_id before it most of existed. So get its old values from the existence hash.
      #If there was nothing it didn't exist so create a new one. Also it only creates a new one if alive is set to true.
      #This check is overkill really, but its just to be safe.
      if old_key
        hash = self.class.get_existence_hash(self.send("#{self.class.route_id}_was"))
        Rails.cache.delete("#{dcname}_existence_hash/#{old_key}")
      elsif alive
        flag[:count] = flag[:count] + 1
        flag[:space] = flag[:space] + 1
        hash = {:type => self.has_attribute?('type') ? self.type : self.class, :num => 0, :pos => flag[:space]}
      end

      #If the record is not being destroyed add new route_id to existence hash
      if alive
        Rails.cache.write("#{dcname}_existence_hash/#{new_key}", hash)
        Rails.cache.write("#{dcname}_existence_hash/#{hash[:pos]}", {:key => new_key})
      else
        if hash[:pos] == flag[:space]
          flag[:space] = flag[:space] - 1
        end
        flag[:count] = flag[:count] - 1
        Rails.cache.delete("#{dcname}_existence_hash/#{hash[:pos]}")
      end

      Rails.cache.write("#{dcname}_existence_hash_flag", flag)

    end

  end
end
