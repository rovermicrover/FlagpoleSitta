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
        Rails.cache.read(app_hash_namespace + key.to_s)
      end

      def flagpole_cache_write key, value
        Rails.cache.write(app_hash_namespace + key.to_s, value)
      end

      def flagpole_cache_delete key
        Rails.cache.delete(app_hash_namespace + key.to_s)
      end

      def flagpole_cache_exist? key
        Rails.cache.exist?(app_hash_namespace + key.to_s)
      end

    end
  end

end