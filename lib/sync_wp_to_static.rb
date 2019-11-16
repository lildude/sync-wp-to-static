#!/usr/bin/env ruby
# frozen_string_literal: true

require 'colorize'
require 'date'
require 'json'
require 'octokit'
require 'httparty'
require 'reverse_markdown'

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

  def repo_has_post?(repo, filename)
    res = client.search_code("filename:#{filename} repo:#{repo} path:_posts")
    return false if res.total_count.zero?

    true
  end

  # TODO: reimplement this to pull in a user-specified ERB template
  def markdown_content(post)
    tags = post.tags
    tags = parse_hashtags(post.content.rendered) if tags.empty?

    unless tags.empty?
      tags_array = %w[tags:]
      tags.each do |tag|
        next if %w[run tech].include? tag

        tags_array << tag
      end
      tags_fm = tags_array.join("\n- ")
    end

    title = "title: #{post.title.rendered}" unless post.title.rendered.empty?
    content = ReverseMarkdown.convert(post.content.rendered.gsub(/#\w+/, ''))
    date = DateTime.parse(post.date).strftime('%F %T %z')
    layout = post.format == 'aside' ? 'note' : 'post'
    <<~MARKDOWN.chomp
      ---
      layout: #{layout}
      date: #{date}
      type: #{post.type}
      #{tags_fm}
      #{title}
      ---

      #{content}
    MARKDOWN
  end

  def add_files_to_repo(repo, files = {})
    latest_commit_sha = client.ref(repo, 'heads/master').object.sha
    base_tree_sha = client.commit(repo, latest_commit_sha).commit.tree.sha

    new_tree = files.map do |path, content|
      Hash(
        path: path,
        mode: '100644',
        type: 'blob',
        sha: client.create_blob(repo, content, 'base64')
      )
    end

    new_tree_sha = client.create_tree(repo, new_tree, base_tree: base_tree_sha).sha
    new_commit_sha = client.create_commit(repo, 'New WP sync\'d post', new_tree_sha, latest_commit_sha).sha
    client.update_ref(repo, 'heads/master', new_commit_sha)
end

  def delete_wp_posts(post_ids)
      headers = { 'Authorization': "Bearer #{ENV['WORDPRESS_TOKEN']}" }
      post_ids.each do |pid|
        uri = "#{ENV['WORDPRESS_ENDPOINT']}/posts/#{pid}"
        HTTParty.delete(uri, headers: headers, raise_on: [403, 404, 500])
      end
    rescue HTTParty::ResponseError => e
      raise "Problem deleting post: Code #{e.response.code} - #{e.response.message}"
    end

  def run
    # Check we have tokens
    tokens?
    # Get all Wordpress posts - assumes there aren't many so we don't bother with paging
    return 'Nothing new'.blue if wp_posts.empty?

    markdown_files = {}
    wp_pids = []
    github_repo = ENV['WORDPRESS_REPO']
    wp_posts.each do |post|
      github_repo = repo(parse_hashtags(post.content.rendered))
      post_filename = filename(post)
      # Next if we have a post in GitHub repo already
      next if repo_has_post?(github_repo, post_filename)

      markdown_files[post_filename] = Base64.encode64(markdown_content(post))
      wp_pids << post.id
    end

    # Add posts to repo in one commit
    add_files_to_repo(github_repo, markdown_files)
    # Remove Wordpress posts
    delete_wp_posts(wp_pids)

    "Sync'd Wordpress posts #{wp_pids.join(', ')} to GitHub #{github_repo}".green
  end
end

# :nocov:
#### All the action happens here ####
if $PROGRAM_NAME == __FILE__
  begin
    puts SyncWpToStatic.new.run
  rescue RuntimeError => e
    warn "Error: #{e}".red
    exit 1
  end
end
# :nocov:
