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
        Rails.cache.read(key.to_s)
      end

      def flagpole_cache_write key, value
        Rails.cache.write(key.to_s, value)
      end

      def flagpole_cache_delete key
        Rails.cache.delete(key.to_s)
      end

      def flagpole_cache_exist? key
        Rails.cache.exist?(key.to_s)
      end

    end
  end

end