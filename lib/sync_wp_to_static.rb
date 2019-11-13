# frozen_string_literal: true

require 'colorize'
require 'date'
require 'json'
require 'octokit'
require 'httparty'

# Class that syncs Wordpress posts to a static site's GitHub repo
class SyncWpToStatic
  def client
    @client ||= Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
  end

  def tokens?
    raise 'Missing auth env vars for tokens' unless ENV['WORDPRESS_TOKEN'] && ENV['WORDPRESS_ENDPOINT'] && ENV['GITHUB_TOKEN']

    true
  end

  def wp_posts
    @wp_posts ||=
      begin
        uri = "#{ENV['WORDPRESS_ENDPOINT']}/posts"
        response = HTTParty.get(uri, format: :plain, raise_on: [400, 403, 404, 500])
        JSON.parse(response, object_class: OpenStruct)
      rescue HTTParty::ResponseError => e
        raise "Problem accessing #{uri}: #{e.message}"
      end
  end

  def parse_hashtags(string)
    string.scan(/#(\w+)/).flatten
  end

  # Use a slugified title or a number based on the date if no title
  def filename(post)
    date = DateTime.parse(post.date)
    fn =
      if post.title.rendered.empty?
        date.strftime('%s').to_i % (24 * 60 * 60)
      else
        slug = post.title.rendered.downcase.gsub('/[\s.\/_]/', ' ').gsub(/[^\w\s-]/, '').squeeze(' ').tr(' ', '-').chomp('-')
        "#{date.strftime('%F')}-#{slug}"
      end

    "#{fn}.md"
  end
end
