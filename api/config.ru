require 'bundler'
require 'fileutils'
require 'logger'
require 'securerandom'

Bundler.require
require_relative 'app'

::Logger.class_eval { alias_method(:write, :<<) unless respond_to?(:write) }

logger = Logger.new(File.join(LOG_DIR, "#{ENV['RACK_ENV']}.log"), 'daily')

use Rack::LtsvLogger, logger
use Rack::PostBodyContentTypeParser

use Rack::Lineprof if ENV['RACK_ENV'] == 'development'

default_session_expire_sec = 1.week.to_i

if ENV['API_SESSION_USE_REDIS']
  use Rack::Session::Redis,
      redis_server: ENV.fetch('API_SESSION_REDIS_SERVER', 'redis://127.0.0.1:6379/0/rack:session'),
      expire_after: ENV.fetch('API_SESSION_EXPIRE_SEC', default_session_expire_sec).to_i
else
  use Rack::Session::Cookie,
      key: ENV.fetch('API_SESSION_COOKIE_KEY', 'rack.session'),
      secret: ENV.fetch('API_SESSION_COOKIE_SECRET') { SecureRandom.hex(64) },
      expire_after: ENV.fetch('API_SESSION_EXPIRE_SEC', default_session_expire_sec).to_i
end

run App