module FlagpoleSitta
  class Engine < Rails::Engine
    initializer "flagpole_sitta.load_app_instance_data" do |app|
      FlagpoleSitta.setup do |config|
        config.app_root = app.root
      end
    end
    initializer "flagpole_sitta.load_static_assets" do |app|
      app.middleware.use ::ActionDispatch::Static, "#{root}/public"
    end
  end
end