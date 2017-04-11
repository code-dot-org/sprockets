# frozen_string_literal: true
require 'sprockets/asset'
require 'sprockets/bower'
require 'sprockets/cache'
require 'sprockets/configuration'
require 'sprockets/digest_utils'
require 'sprockets/errors'
require 'sprockets/loader'
require 'sprockets/npm'
require 'sprockets/path_dependency_utils'
require 'sprockets/path_digest_utils'
require 'sprockets/path_utils'
require 'sprockets/resolve'
require 'sprockets/server'
require 'sprockets/source_map_utils'
require 'sprockets/uri_tar'

module Sprockets
  # `Base` class for `Environment` and `CachedEnvironment`.
  class Base
    include PathUtils, PathDependencyUtils, PathDigestUtils, DigestUtils, SourceMapUtils
    include Configuration
    include Server
    include Resolve, Loader
    include Bower
    include Npm

    # Get persistent cache store
    attr_reader :cache

    # Set persistent cache store
    #
    # The cache store must implement a pair of getters and
    # setters. Either `get(key)`/`set(key, value)`,
    # `[key]`/`[key]=value`, `read(key)`/`write(key, value)`.
    def cache=(cache)
      @cache = Cache.new(cache, logger)
    end

    # Return an `CachedEnvironment`. Must be implemented by the subclass.
    def cached
      raise NotImplementedError
    end
    alias_method :index, :cached

    # Internal: Compute digest for path.
    #
    # path - String filename or directory path.
    #
    # Returns a String digest or nil.
    def file_digest(path)
      if stat = self.stat(path)
        # Caveat: Digests are cached by the path's current mtime. Its possible
        # for a files contents to have changed and its mtime to have been
        # negligently reset thus appearing as if the file hasn't changed on
        # disk. Also, the mtime is only read to the nearest second. It's
        # also possible the file was updated more than once in a given second.
        key = UnloadedAsset.new(path, self).file_digest_key(stat.mtime.to_i)
        cache.fetch(key) do
          self.stat_digest(path, stat)
        end
      end
    end

    # Find asset by logical path or expanded path.
    def find_asset(*args)
      uri, _ = resolve(*args)
      if uri
        load(uri)
      end
    end

    def find_all_linked_assets(*args)
      return to_enum(__method__, *args) unless block_given?

      asset = find_asset(*args)
      return unless asset

      yield asset
      stack = asset.links.to_a
      resolve_assets(stack).each do |asset|
        yield asset
      end

      nil
    end

    def resolve_assets(links)
      return to_enum(__method__, links) unless block_given?

      promises = links.map do |uri|
        Concurrent::Promise.execute(executor: executor) do
          yield asset = load(uri)
          resolve_assets(asset.links.to_a).each do |linked_asset|
            yield linked_asset
          end
        end
      end
      promises.each(&:wait!)
    end

    # Preferred `find_asset` shorthand.
    #
    #     environment['application.js']
    #
    def [](*args)
      find_asset(*args)
    end

    # Find asset by logical path or expanded path.
    #
    # If the asset is not found an error will be raised.
    def find_asset!(*args)
      uri, _ = resolve!(*args)
      if uri
        load(uri)
      end
    end

    # Pretty inspect
    def inspect
      "#<#{self.class}:0x#{object_id.to_s(16)} " +
        "root=#{root.to_s.inspect}, " +
        "paths=#{paths.inspect}>"
    end

    def compress_from_root(uri)
      URITar.new(uri, self).compress
    end

    def expand_from_root(uri)
      URITar.new(uri, self).expand
    end
  end
end
