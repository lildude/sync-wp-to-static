# frozen_string_literal: true

require 'simplecov'
require 'coveralls'
SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.start do
  add_filter 'vendor'
end

require 'minitest/autorun'
require 'minitest/pride'
require 'webmock/minitest'
require './lib/sync_wp_to_static'

ENV['RACK_ENV'] ||= 'test'

class SyncWpToStaticMethodsTest < Minitest::Test
  def setup
    ENV['GITHUB_TOKEN'] = '0987654321'
    ENV['WORDPRESS_TOKEN'] = '1234567890'
    ENV['WORDPRESS_ENDPOINT'] = 'https://public-api.wordpress.com/wp/v2/sites/foobar.wordpress.com'
  end

  def test_client
    assert_kind_of Octokit::Client, SyncWpToStatic.new.client
    assert_equal '0987654321', SyncWpToStatic.new.client.access_token
  end
  def test_it_works
    obj = SyncWpToStatic.new
    assert obj
  end
end
