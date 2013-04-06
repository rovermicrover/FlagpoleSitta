module FlagpoleSittaHelper

  ##
  #AR - cache_sitta helper
  #NOTE This is not safe for .builder xml files.
  #Options
  #
  #:section
  #The section of the page the cache represents. This is
  #best used in connection with -content_for. Can be any
  #string you want it to be. If not provided will default to
  #body. Also looks for the calls using sections. Will assume calls
  #are in the instance variable '@#{options[:section]_calls'
  #
  #:model
  #The model of the object, or objects that you want to link
  #the cache too. Pass the actually model, or an array of models.
  #Must also have a corresponding route_id. If model is an array, 
  #route_id must also be an array of equal length. model[i] is 
  #connected to route_id[i].
  #
  #:route_id
  #The unique identifier of the object, most likely what you route on
  #for showing the object or objects that you want to link
  #the cache too. Pass as a string, or an array of strings.
  #Must also have a corresponding model. If route_id is an array, 
  #model must also be an array of equal length. model[i] is 
  #connected to route_id[i].
  #
  #:models_in_index
  #Use this if the fragment you are rendering is an index
  #pass it all the different types of models/classes could be
  #included in the index. All the include classes must have cache
  #sitta enabled. The cache for the used index pages will then be
  #wiped clear when anyone of these models/classes has an object
  #created or updated.
  #
  #:index_only
  #Use this if the cache should not be associated with any object,
  #but rather only a model. Use this if your cache is an index, or
  #can be 'random'.
  #
  #:sub_route_id
  #Use this if options on the url can result in a difference in
  #the cache. So if you had an page where you could pass
  #in a year and month would be a great place for this.
  #That way your caching each possible version of the page
  #instead of just one.
  #
  #:scope which will add a 'scope' to a :models_in_index cache, 
  #which will cause the cache to only be destroyed if an object with in its 'scope' is create, 
  #updated or destroyed. Like :model and :route_id for each model there must be a corresponding route_id. 
  #If you don't want a scope on every model then just make the index model's scope nil.
  #The 'scope' can only be arguments for a where call. Which means it will either be a hash or an array.
  #Scopes should be used sparling because in order to verify them on save they require a call to the database, 
  #and while it boils down to a call by id, they can still add up if you don't pay attention.
  #
  #:times which allows you to use cache sitta more efficently with indexes based on time. Pass it the models
  #which you are index on a time field.
  #
  #:time pass it through a hash the :year, :month, :day, and :hour your indexing on. You can choose to index on any of these
  #but if you index on hour you must provide :day, :month, :year also. If you index on day, you must provide :month: year also.
  #etc etc.
  def cache_sitta  options={}, &block

    controller = options[:controller] || params[:controller]
    action = options[:action] ? options[:action].first[0] :  params[:action]
    action_vars = options[:action] ? options[:action].first[1] :  options[:action_vars]

    key = "views/#{controller}/#{action}/#{action_vars}/#{options[:section]}"

    key = FlagpoleSitta::CommonFs.flagpole_full_key(key)

    calls = instance_variable_get(
      "@" + options[:section] + "_calls"
    )

    hash = benchmark("Read fragment #{key} :: FlagpoleSitta") do
      hash = FlagpoleSitta::CommonFs.flagpole_cache_read(key)
    end

    if hash && Rails.application.config.action_controller.perform_caching
      content = hash[:content]
    else
      Redis::Mutex.with_lock(key + "/lock") do

        hash = benchmark("Lock Acquired Reading fragment #{key} :: FlagpoleSitta") do
          hash = FlagpoleSitta::CommonFs.flagpole_cache_read(key)
        end

        if hash.nil? || !(Rails.application.config.action_controller.perform_caching)

          content = benchmark("Write fragment #{key} :: FlagpoleSitta") do
            #NOTE This is not safe for .builder xml files, and using capture here is why.
            #Its either this or a really complicated hack, from the rails source code, which
            #at the moment I don't feel comfortable using. Waiting for an official solution for
            #the ability to use capture with .builders.
            content = capture do

              if calls
                calls.each do |c|
                  if instance_variable_get("@#{c[0]}").nil?
                    instance_variable_set("@#{c[0]}", c[1].call())
                  end
                end
              end

              yield

            end

            #AR - If the cache is an index or includes an index
            #then models_in_index should be passed with all the
            #models that could show up in the index.
            #Then on save of any model include here this index will be cleared.
            #This can also be used for fragments where there are just so many objects,
            #that while its not an index, there isn't a clear way expect to nuke it when
            #any of the model types involved are updated.

            associated = Array.new

            if options[:index]
              cache_sitta_associations :index, associated, key, options[:index]
            elsif options[:times]
              cache_sitta_associations :times, associated, key, options[:times]
            elsif options[:objects]
              cache_sitta_associations :objects, associated, key, options[:objects]
            end

            if Rails.application.config.action_controller.perform_caching
              FlagpoleSitta::CommonFs.flagpole_cache_write(key, {:content => content, :associated => associated})
            end

            content

          end

        else
          content = hash[:content]
        end

      end

    end

    safe_concat content

  end

  def update_index_array_cache model, key
    model.try(:update_cache_hash, key)
  end

  def update_time_array_cache model, key, time
    model.try(:update_cache_hash, key, :time => time)
  end

  def update_object_array_cache model, key, route_id
    model.try(:update_cache_hash, key, :route_id => route_id)
  end

  def cache_sitta_associations type, associated, key, options
    if options
      options.each do |model, hash|
        if type == :index
          associated << update_index_array_cache(model, key)
        elsif type == :times
          time_string = (hash[:year] ? hash[:year].to_i.to_s : '') + (hash[:month] ? ('/' + hash[:month].to_i.to_s) : '') + (hash[:day] ? ('/' + hash[:day].to_i.to_s) : '') + (hash[:hour] ? ('/' + hash[:hour].to_i.to_s) : '')
          associated << update_time_array_cache(model, key, time_string)
        elsif type == :objects
          route_id = hash[:route_id]
          associated << update_object_array_cache(model, key, route_id)
        end
        if hash && hash[:assoc] && hash[:location]

          objects = instance_variable_get(hash[:location])
          objects = objects.respond_to?(:each) ? objects : ([] << objects)

          objects.each do |o|

            assoc = hash[:assoc].respond_to?(:each) ? hash[:assoc] : ([] << hash[:assoc])
            assoc.each do |a, scope|

              if o.class.reflect_on_association(a).collection?
                assoc_objs = o.send(a).where(scope)
              else
                assoc_objs = o.send(a)
              end
              if assoc_objs.present?
                assoc_objs = assoc_objs.respond_to?(:each) ? assoc_objs : ([] << assoc_objs)
                assoc_objs.each do |ao|
                  associated << update_object_array_cache(ao.class, key, ao.route_id)
                end
              end
            end
          end
        end
      end
    end
  end

end
