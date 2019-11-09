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

class SyncWpToStaticTest < Minitest::Test
  def test_it_works
    obj = SyncWpToStatic.new
    assert obj
  end
end
