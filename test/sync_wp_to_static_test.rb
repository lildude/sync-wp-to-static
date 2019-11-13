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

  def test_tokens
    assert SyncWpToStatic.new.tokens?

    ENV['WORDPRESS_TOKEN'] = nil
    ENV['GITHUB_TOKEN'] = nil

    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.tokens? }
    assert_match 'Missing auth env vars for tokens', exception.message
  end

  def test_wp_posts
    stub_request(:get, /foobar.wordpress.com/)
      .to_return(status: 200, body: JSON.generate([]), headers: {})
    assert_equal [], SyncWpToStatic.new.wp_posts

    stub_request(:get, /foobar.wordpress.com/)
      .to_raise(HTTParty::ResponseError.new('404 Not Found'))
    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.wp_posts }
    expected_message = <<~MSG.chomp
      Problem accessing #{ENV['WORDPRESS_ENDPOINT']}/posts: 404 Not Found
    MSG
    assert_equal expected_message, exception.message
  end
  def test_it_works
    obj = SyncWpToStatic.new
    assert obj
  end
end
