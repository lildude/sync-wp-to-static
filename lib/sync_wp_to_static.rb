# frozen_string_literal: true

require 'colorize'
require 'date'
require 'json'
require 'octokit'
require 'open-uri'

# Class that syncs Wordpress posts to a static site's GitHub repo
class SyncWpToStatic
  def client
    @client ||= Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
  end

  def tokens?
    raise 'Missing auth env vars for tokens' unless ENV['WORDPRESS_TOKEN'] && ENV['WORDPRESS_ENDPOINT'] && ENV['GITHUB_TOKEN']

    true
  end
end
