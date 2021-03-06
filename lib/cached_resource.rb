require 'ostruct'

require 'nilio'
require 'active_support/concern'
require 'cached_resource/cached_resource'
require 'cached_resource/configuration'
require 'cached_resource/caching'
require 'cached_resource/query_caching'
require 'cached_resource/version'
#require 'parse_resource/query'

module CachedResource
  # nada
end

# Include model methods in ActiveResource::Base
class ParseResource::Base
  include CachedResource::Model
end

class Query
  include CachedResource::QueryCache
end
