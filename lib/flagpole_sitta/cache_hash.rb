class CacheHash

  def initialize model, route_id = nil
    @model = model.respond_to?(:constantize) ? model.constantize : model

    @route_id = route_id

    @key_base = hash_cache_key_gen @route_id

    @caches = Redis::HashKey.new(@key_base, :marshal => true)

  end

  def add key, options={}
    Rails.logger.info "#{key} is being associated with #{@key_base}"
    @caches[key] = {:placeholder => "For Now"}

    @key_base

  end

  def destory options={}
    Rails.logger.info "#{@key_base} is being cleared"
    @caches.each do |key, hash|
      Redis::Mutex.with_lock(key + "/lock") do
        #A Check in Case there is some type of cache failure
        if hash.present?

          #Get all the associated.
          associated = FlagpoleSitta::CommonFs.flagpole_cache_read(key)[:associated]
          Rails.logger.info "#{key} is being cleared"
          #Destroy the actually cache
          FlagpoleSitta::CommonFs.flagpole_cache_delete(key)
    
          associated.each do |associated_base_key|
            associated_caches = Redis::HashKey.new(associated_base_key, :marshal => true)
            associated_caches.delete(key)
          end

        end
      end

    end

    nil

  end


  private

  #Options :emptystack will make it generate a key for the emptystack instead of the general cache array.
  def hash_cache_key_gen route_id

    mid_key = mid_key_gen route_id

    key = "#{@model}/#{mid_key}"

    key = FlagpoleSitta::CommonFs.flagpole_full_key(key)

  end

  #Determines if its for an index array or show array.
  def mid_key_gen route_id
    if route_id
      mid_key = "#{route_id}/BoundedHash"
    else
      mid_key = "IndexHash"
    end
  end

end