module FlagpoleSittaHelper

  def update_index_array_cache model, key, scope=nil
    model.try(:update_cache_hash, key, :scope => scope)
  end

  def update_show_array_cache model, key, route_id
    model.try(:update_cache_hash, key, :route_id => route_id)
  end

  def update_time_array_cache model, key, time
    model.try(:update_cache_hash, key, :time => time)
  end

  #In case an unsafe param gets passed. 
  #Don't want to save SQL injection attempts in the cache.
  def clean_options options={}

    result = Hash.new

    options.each do |k,v|
      #First make sure they aren't trying to put some nasty html in.
      begin
        clean_v = sanitize(v)
      rescue
        clean_v = v
      end

      #Scopes are then sanitized before they are placed in via the methods on the model

      #Next try to make sure they aren't trying to inject anything via a dynamic scope



      result[k] = clean_v

    end

    result

  end

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
  #:time_models which allows you to use cache sitta more efficently with indexes based on time. Pass it the models
  #which you are index on a time field.
  #
  #:time pass it through a hash the :year, :month, :day, and :hour your indexing on. You can choose to index on any of these
  #but if you index on hour you must provide :day, :month, :year also. If you index on day, you must provide :month: year also.
  #etc etc.
  def cache_sitta  options={}, &block

    options = clean_options(options)

    if options[:route_id].class.eql?(Array)
      main_route_id = options[:route_id][0]
    else
      main_route_id = options[:route_id]
    end

    if options[:model]

      if options[:model].class.eql?(Array)
        main_model = options[:model][0]
      else
        main_model = options[:model]
      end

    elsif options[:time_models]

      if options[:time_models].class.eql?(Array)
        main_model = options[:time_models][0]
      else
        main_model = options[:time_models]
      end

    elsif options[:models_in_index]

      if options[:models_in_index].class.eql?(Array)
        main_model = options[:models_in_index][0]
      else
        main_model = options[:models_in_index]
      end
      
    end

    main_model = main_model.respond_to?(:constantize) ? main_model.constantize : main_model

    if options[:time]
      time_string = (options[:time][:year] ? options[:time][:year].to_i.to_s : '') + (options[:time][:month] ? ('/' + options[:time][:month].to_i.to_s) : '') + (options[:time][:day] ? ('/' + options[:time][:day].to_i.to_s) : '') + (options[:time][:hour] ? ('/' + options[:time][:hour].to_i.to_s) : '')
    else
      time_string = nil
    end

    action = options[:action] || params[:action]

    key = "views/#{main_model}/#{action}"

    key = key + (main_route_id ? ('/' + main_route_id) : '')

    key = key + (options[:sub_route_id] ? ('/' + options[:sub_route_id]) : '')

    key = key + (time_string.present? ? ('/' + time_string) : '')

    key = key + (options[:section] ? ('/' + options[:section]) : '')

    calls = instance_variable_get(
      "@" + (options[:section] ? options[:section] : 'body') + "_calls"
    )

    hash = benchmark("Read fragment #{key} :: FlagpoleSitta") do
      hash = FlagpoleSitta::CommonFs.flagpole_cache_read(key)
    end

    if hash
      content = hash[:content]
    else
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

        if options[:models_in_index].class.eql?(Array)
          options[:models_in_index].each_index do |i|
            m = options[:models_in_index][i]
            if options[:scope]
              scope = options[:scope][i]
            end
            processed_model = m.respond_to?(:constantize) ? m.constantize : m
            associated << update_index_array_cache(processed_model, key, scope)
          end
        elsif options[:models_in_index]
          processed_model = options[:models_in_index].respond_to?(:constantize) ? options[:models_in_index].constantize : options[:models_in_index]
          associated << update_index_array_cache(processed_model, key, options[:scope])
        end

        if options[:time_models] && options[:time]
          if options[:time_models].class.eql?(Array)
            options[:time_models].each do |m|
              associated << update_time_array_cache(m, key, time_string)
            end
          else
            associated << update_time_array_cache(options[:time_models], key, time_string)
          end
        end

        if !options[:index_only] && options[:route_id]
          if options[:route_id].class.eql?(Array) && options[:model].class.eql?(Array)
            options[:model].each_index do |i|
              associated << update_show_array_cache(options[:model][i], key, options[:route_id][i])
            end
          else
            associated << update_show_array_cache(main_model, key, main_route_id)
          end
        end

        FlagpoleSitta::CommonFs.flagpole_cache_write(key, {:content => content, :associated => associated})

        content

      end

    end

    safe_concat content

  end

end
