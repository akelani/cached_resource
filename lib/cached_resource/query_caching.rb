module CachedResource
  # The Caching module is included in ActiveResource and
  # handles caching and recaching of responses.

  module QueryCaching
    extend ActiveSupport::Concern

    included do
      class << self
      end

      alias_method_chain :all, :cache

    end

    module InstanceMethods
      def all_with_cache(*arguments)
        Rails.logger.debug("All with cache...")
        arguments << {} unless arguments.last.is_a?(Hash)
        should_reload = arguments.last.delete(:reload) || !self.class.cached_resource.enabled
        arguments.pop if arguments.last.empty?
        key = self.class.cache_key(self.criteria)
        Rails.logger.debug("Key: #{key}")
        should_reload ? all_via_reload(key, *arguments) : all_via_cache(key, *arguments)
      end

      def all_via_reload(key, *arguments)
        self.class.cached_resource.logger.debug("Getting all via reload...")
        object = all_without_cache(*arguments)
        self.class.cache_collection_synchronize(object, *arguments) if self.class.cached_resource.collection_synchronize
        self.class.cache_write(key, object)
        self.class.cache_read(key)
      end

      def all_via_cache(key, *arguments)
        self.class.cache_read(key) || all_via_reload(key, *arguments)
      end
    end

    module ClassMethods
      # Find a resource using the cache or resend the request
      # if :reload is set to true or caching is disabled.

      #private

      # Try to find a cached response for the given key.  If
      # no cache entry exists, send a new request.

      def all_via_cache(key, *arguments)
        cache_read(key) || all_via_reload(key, *arguments)
      end

      # Re/send the request to fetch the resource. Cache the response
      # for the request.

      def all_via_reload(key, *arguments)
        cached_resource.logger.debug("Getting all via reload...")
        object = all_without_cache(*arguments)
        cache_collection_synchronize(object, *arguments) if cached_resource.collection_synchronize
        cache_write(key, object)
        cache_read(key)
      end

      # If this is a pure, unadulterated "all" request
      # write cache entries for all its members
      # otherwise update an existing collection if possible.
      def cache_collection_synchronize(object, *arguments)
        if object.is_a? Array
          update_singles_cache(object)
          # update the collection only if this is a subset of it
          update_collection_cache(object) unless is_collection?(*arguments)
        else
          update_collection_cache(object)
        end
      end

      # Update the cache of singles with an array of updates.
      def update_singles_cache(updates)
        updates = Array(updates)
        updates.each { |object| cache_write(object.send(:id), object) }
      end

      # Update the "mother" collection with an array of updates.
      def update_collection_cache(updates)
        updates = Array(updates)
        collection = cache_read(cached_resource.collection_arguments)

        if collection && !updates.empty?
          store = CachedResource::Configuration::ORDERED_HASH.new
          index = collection.inject(store) { |hash, object| hash[object.send(:id)] = object; hash }
          updates.each { |object| index[object.send(:id)] = object }
          cache_write(cached_resource.collection_arguments, index.values)
        end
      end

      # Determine if the given arguments represent
      # the entire collection of objects.
      def is_collection?(*arguments)
        arguments == cached_resource.collection_arguments
      end

      # Read a entry from the cache for the given key.
      # The key is processed to make sure it is valid.
      def cache_read(key)
        key = cache_key(Array(key)) unless key.is_a? String
        object = cached_resource.cache.read(key).try do |cache|
          if cache.is_a? Enumerable
            cache.map { |record| full_dup(record) }
          elsif cache.duplicable?
            if cache.is_a? Query
              cache.dup
            else
              full_dup(cache)
            end
          else
            cache
          end
        end
        object && cached_resource.logger.debug("#{CachedResource::Configuration::LOGGER_PREFIX} READ #{key} - #{object.inspect}")
        object
      end

      # Write an entry to the cache for the given key and value.
      # The key is processed to make sure it is valid.
      def cache_write(key, object)
        key = cache_key(Array(key)) unless key.is_a? String
        result = cached_resource.cache.write(key, object, :expires_in => cached_resource.generate_ttl)
        result && cached_resource.logger.debug("#{CachedResource::Configuration::LOGGER_PREFIX} WRITE #{key} - #{object.inspect}")
        result
      end

      # Generate the request cache key.
      def cache_key(*arguments)
        "#{name.parameterize.gsub("-", "/")}/#{arguments.join('/')}".downcase
      end

      # Make a full duplicate of an ActiveResource record.
      # Currently just dups the record then copies the persisted state.
      def full_dup(record)
        record.dup.tap do |o|
          o.instance_variable_set(:@persisted, record.persisted?)
        end
      end

    end
  end
end
