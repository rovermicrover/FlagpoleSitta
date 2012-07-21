module FlagpoleSitta
  module ControllerSitta

    extend ActiveSupport::Concern

    ##
    #Creates adds the block or provided proc or lamdba to the given
    #section or sections call array. These calls backs are then used by
    #the cache_sitta view helper.
    #
    #:section the section or sections the block will be connected too. Array or String.
    #
    #:name the name of the instance variable the returned value of the block String
    #will be stored at. Ie 'blog' would result in @blog.
    #
    #:block you can pass in an already defined proc or lamdba instead of a block. Proc pr lamdba
    #
    def calls_sitta options={}, &block

      options[:section] ? (section = options[:section]) : (section = "body")

      options[:name] ? (name = options[:name]) : (name = "object")

      if section.class.eql?(Array)
        section.each do |s|
          if options[:block]
            calls_sitta_set(s, name, options[:block])
          else
            calls_sitta_set(s, name, block)
          end
        end
      else
        if options[:block]
          calls_sitta_set(section, name, options[:block])
        else
          calls_sitta_set(section, name, block)
        end
      end

    end

    ##
    #Takes the predefined blocks from one section and adds them to one or more other sections.
    #
    #:frome_section from where you want to copy. String
    #
    #:to_section the section or sections you want to copy to. String or Array.
    def calls_sitta_append options={}

      calls_sitta_init options[:from_section]

      if options[:to_section].class.eql?(Array)
        options[:to_section].each do |s|
          calls_sitta_init s
          instance_variable_set("@#{s}_calls",
            instance_variable_get("@#{s}_calls") + instance_variable_get("@#{options[:from_section]}_calls")
          )
        end
      else
        calls_sitta_init options[:to_section]
        instance_variable_set("@#{options[:to_section]}_calls",
          instance_variable_get("@#{options[:to_section]}_calls") + instance_variable_get("@#{options[:from_section]}_calls")
        )
      end

    end

    ##
    # Make sure the instance variable has the correct starting value.
    def calls_sitta_init section
      if !instance_variable_defined?("@#{section}_calls")
        instance_variable_set("@#{section}_calls", [])
      end
    end

    ##
    # A method to help dry out calls_sitta
    def calls_sitta_set section, name, block
      
      calls_sitta_init section

      instance_variable_set("@#{section}_calls",
        instance_variable_get("@#{section}_calls") + [[name, block]]
      )
    end

  end

end

ActionController::Base.send(:include, FlagpoleSitta::ControllerSitta)