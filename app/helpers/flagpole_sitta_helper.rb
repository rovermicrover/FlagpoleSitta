module FlagpoleSittaHelper

  def update_index_array_cache model, key
    model.try(:update_index_array_cache, key)
  end

  def update_show_array_cache model, key, route_id
    model.try(:update_show_array_cache, key, route_id)
  end

  #AR - cache_sitta helper

  #NOTE This is not safe for .builder xml files.

  #Options are for cache_sitta
  
  #key_args, passed to route_id if its a proc or lamdba
  #all args must be passed in this manner if proc or lamdba
  #so start your proc or lamdba with |options = {}|

  #call_args, passed to call_path if its a proc of lamdba
  #all args must be passed in this manner if proc or lamdba
  #so start your proc or lamdba with |options = {}|

  #models_in_index
  #Use this if the fragment you are rendering is an index
  #pass it all the different types of models/classes could be
  #included in the index. All the include classes must have cache
  #sitta enabled. The cache for the used index pages will then be
  #wiped clear when anyone of these models/classes has an object
  #created or updated.
  def cache_sitta  options={}, &block

    #AR - If its a string, then just use that value, other wise it
    #assumes that the route_id is a proc or lamdba and call its
    #with the provide args.

    if options[:route_id_args]
      options[:route_id] = options[:route_id].call(options[:route_id_args])
    elsif options[:route_id].class.eql?(Proc)
      options[:route_id] = options[:route_id].call()
    end

    if options[:route_id].class.eql?(Array)
      main_route_id = options[:route_id][0]
    else
      main_route_id = options[:route_id]
    end


    #Use subroute idea if the view can differ on things like current day, or any type of passed params that can effect how
    #the page will look.
    if options[:sub_route_id_args]
      options[:sub_route_id] = options[:sub_route_id].call(options[:sub_route_id_args])
    elsif options[:sub_route_id_args].class.eql?(Proc)
      options[:sub_route_id] = options[:sub_route_id].call()
    end

    if options[:model]
      if options[:model_args]
        options[:model] = options[:model].call(options[:model_args])
      elsif options[:model].class.eql?(Proc)
        options[:model] = options[:model].call()
      end

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
              if options[:calls_args]
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
