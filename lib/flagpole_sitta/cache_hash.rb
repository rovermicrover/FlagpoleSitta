class CacheHash

  def initialize model, route_id = nil
    @model = model.responsed_to?(:constantize) ? model.constantize : model

    @route_id = route_id

    @key_base = array_cache_key_gen @route_id

    @caches = Redis::HashKey.new(@key_base, :marshal => true)

  end

  def add key, options={}

    @caches[key] = {:scope => options[:scope]}

    @key_base

  end

  def destory options={}
    @caches.each do |key, hash|
      #A Check in Case there is some type of cache failure, or it is an empty spot, also if it has no scope, or it falls in scope
      if hash.present? && (hash[:scope].nil? || in_scope(hash[:scope], options[:obj]))

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

    nil

  end


  private

  def in_scope scope, obj

    obj.class.where(scope).exists?(obj.id)

  end

    #Options :emptystack will make it generate a key for the emptystack instead of the general cache array.
  def array_cache_key_gen route_id

    mid_key = mid_key_gen route_id

    key = "#{@model}/#{mid_key}"

    key = FlagpoleSitta::CommonFs.flagpole_full_key(key)

  end

  #Determines if its for an index array or show array.
  def mid_key_gen route_id
    if route_id
      mid_key = "#{route_id}/ShowArray"
    else
      mid_key = "IndexArray"
    end
  end

end