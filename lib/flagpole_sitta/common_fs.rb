module FlagpoleSitta

  class CommonFs

    class << self

      def app_hash_namespace
        "#{Rails.application.class.to_s.split("::").first}/#{Rails.env}/"
      end

      def flagpole_full_key key
        app_hash_namespace + key.to_s
      end

      def flagpole_cache
        Redis::HashKey.new("#{app_hash_namespace}FlagpoleSittaGem/flagpole_cache", :marshal => true)
      end

    end
  end

end