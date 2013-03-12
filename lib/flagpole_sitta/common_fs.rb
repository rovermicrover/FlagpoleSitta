module FlagpoleSitta

  class CommonFs

    class << self

      def app_hash_namespace
        "#{Rails.application.class.to_s.split("::").first}/#{Rails.env}/"
      end

      def flagpole_full_key key
        app_hash_namespace + key.to_s
      end

      def flagpole_cache_read key
        flagpole_cache[key.to_s]
      end

      def flagpole_cache_write key, value
        flagpole_cache[key.to_s] = value
      end

      def flagpole_cache_delete key
        flagpole_cache.delete(key.to_s)
      end

      def flagpole_cache_exist? key
        flagpole_cache.has_key?(key.to_s)
      end

      def flagpole_cache
        Redis::HashKey.new("FlagpoleSittaGem/flagpole_cache", :marshal => true)
      end

    end
  end

end