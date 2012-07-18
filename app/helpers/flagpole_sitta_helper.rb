module FlagpoleSittaHelper

  def update_index_array_cache model, key
    model.try(:update_array_cache, key)
  end

  def update_show_array_cache model, key, route_id
    model.try(:update_array_cache, key, route_id)
  end

  #AR - cache_sitta helper
  #NOTE This is not safe for .builder xml files.
  #Options
  #-------
  #:section
  #The section of the page the cache represents. This is
  #best used in connection with -content_for. Can be any
  #string you want it to be. If not provided will default to
  #body. Also looks for the calls using sections. Will assume calls
  #are in the instance variable '@#{options[:section]_calls'
  #-------
  #:model
  #The model of the object, or objects that you want to link
  #the cache too. Pass the actually model, or an array of models.
  #Must also have a corresponding route_id. If model is an array, 
  #route_id must also be an array of equal length. model[i] is 
  #connected to route_id[i].
  #-------
  #:route_id
  #The unique identifier of the object, most likely what you route on
  #for showing the object or objects that you want to link
  #the cache too. Pass as a string, or an array of strings.
  #Must also have a corresponding model. If route_id is an array, 
  #model must also be an array of equal length. model[i] is 
  #connected to route_id[i].
  #-------
  #:models_in_index
  #Use this if the fragment you are rendering is an index
  #pass it all the different types of models/classes could be
  #included in the index. All the include classes must have cache
  #sitta enabled. The cache for the used index pages will then be
  #wiped clear when anyone of these models/classes has an object
  #created or updated.
  #-------
  #:index_only
  #Use this if the cache should not be associated with any object,
  #but rather only a model. Use this if your cache is an index, or
  #can be 'random'.
  #-------
  #:sub_route_id
  #Use this if options on the url can result in a difference in
  #the cache. So if you had an page where you could pass
  #in a year and month would be a great place for this.
  #That way your caching each possible version of the page
  #instead of just one.
  #-------
  #:calls_args
  #Any args you want to pass to your calls. Can only take one argument.
  #The best idea is to pass an option hash.
  def cache_sitta  options={}, &block

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

    elsif params[:model]

      main_model = params[:model]

    elsif options[:models_in_index]

      if options[:models_in_index].class.eql?(Array)
        main_model = options[:models_in_index][0]
      else
        main_model = options[:models_in_index]
      end
      
    end

    main_model = main_model.respond_to?(:constantize) ? main_model.constantize : main_model

    action = options[:action] || params[:action]

    key = "views/#{main_model}/#{action}"

    key = key + (main_route_id ? ('/' + main_route_id) : '')

    key = key + (options[:sub_route_id] ? ('/' + options[:sub_route_id]) : '')

    key = key + (options[:section] ? ('/' + options[:section]) : '')

    calls = instance_variable_get(
      "@" + (options[:section] ? options[:section] : 'body') + "_calls"
    )

    if content = Rails.cache.read(key)
      #Do nothing the content is ready to render
    else
      #NOTE This is not safe for .builder xml files, and using capture here is why.
      #Its either this or a really complicated hack, from the rails source code, which
      #at the moment I don't feel comfortable using. Waiting for an official solution for
      #the ability to use capture with .builders.
      content = capture do
        #AR - If call_path is an array render each one, other
        #wise just render call_path, because it must
        #be a string or array by this point or something went
        #terribly terribly wrong.

        if calls
          calls.each do |c|
            if instance_variable_get("@#{c[0]}").nil?
              if options[:calls_args] && (c.parameters.length > 0)
                instance_variable_set("@#{c[0]}", c[1].call(options[:calls_args]))
              else
                instance_variable_set("@#{c[0]}", c[1].call())
              end
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

      if options[:models_in_index].class.eql?(Array)
        options[:models_in_index].each do |m|
          processed_m = m.respond_to?(:constantize) ? m.constantize : m
          update_index_array_cache(processed_m, key)
        end
      elsif options[:models_in_index]
        processed_model = options[:models_in_index].respond_to?(:constantize) ? options[:models_in_index].constantize : options[:models_in_index]
        update_index_array_cache(options[:models_in_index], key)
      end

      #AR - Create a link between each declared object and the cache.

      if !options[:index_only] && options[:route_id]
        if options[:route_id].class.eql?(Array) && options[:model].class.eql?(Array)
          options[:model].each_index do |i|
            update_show_array_cache(options[:model][i], key, options[:route_id][i])
          end
        else
          update_show_array_cache(main_model, key, main_route_id)
        end
      end

      Rails.cache.write(key, content)

    end

    safe_concat content

  end

end
