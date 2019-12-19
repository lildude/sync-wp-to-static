# frozen_string_literal: true

require 'colorize'
require 'date'
require 'erb'
require 'json'
require 'octokit'
require 'httparty'
require 'reverse_markdown'

# Class that syncs Wordpress posts to a static site's GitHub repo
class SyncWpToStatic
  def client
    @client ||= Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
  end

  def configured?
    missing_tokens = []
    %w[WORDPRESS_TOKEN WORDPRESS_ENDPOINT GITHUB_TOKEN POST_TEMPLATE].each do |env_var|
      missing_tokens << env_var unless ENV[env_var]
    end

    msg = <<~ERROR_MSG
      Whoops! Looks like you've not finished configuring things.
      Missing: #{missing_tokens.join(', ')} environment variables."
    ERROR_MSG

    raise msg unless missing_tokens.empty?

    true
  end

  def wp_posts
    @wp_posts ||=
      begin
        uri = "#{ENV['WORDPRESS_ENDPOINT']}/posts"
        response = HTTParty.get(uri, format: :plain, raise_on: [400, 403, 404, 500])
        JSON.parse(response, object_class: OpenStruct)
      rescue HTTParty::ResponseError => e
        body = JSON.parse(e.response.body, object_class: OpenStruct)
        raise "Problem accessing #{uri}: #{body.message}"
      end
  end

  def parse_hashtags(string)
    string.scan(/\s+#(\w+)/).flatten
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

  def render_template(post)
    render_binding = binding
    post.tags = parse_hashtags(post.content.rendered) if post.tags.empty?
    content = ReverseMarkdown.convert(post.content.rendered.gsub(/#\w+/, '')) # rubocop:disable Lint/UselessAssignment
    template = File.read(ENV['POST_TEMPLATE'])

    ERB.new(template, trim_mode: '-').result(render_binding)
  end

  def add_files_to_repo(repo, files = {})
    return "Would add #{files.keys.join(', ')} to #{repo}".yellow if ENV['DRY_RUN']

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
    return "Would delete Wordpress posts #{post_ids.join(', ')}".yellow if ENV['DRY_RUN']

    headers = { 'Authorization': "Bearer #{ENV['WORDPRESS_TOKEN']}" }
    post_ids.each do |pid|
      uri = "#{ENV['WORDPRESS_ENDPOINT']}/posts/#{pid}"
      HTTParty.delete(uri, headers: headers, raise_on: [403, 404, 500])
    end
  rescue HTTParty::ResponseError => e
    body = JSON.parse(e.response.body, object_class: OpenStruct)
    raise "Problem deleting post: #{body.message}"
  end

  def run
    # Check we have tokens
    configured?
    # Get all Wordpress posts - assumes there aren't many so we don't bother with paging
    return 'Nothing new'.blue if wp_posts.empty?

    markdown_files = {}
    wp_pids = []
    github_repo = ENV['GITHUB_REPOSITORY']
    wp_posts.each do |post|
      tags = Set.new(post.tags) + parse_hashtags(post.content.rendered)
      if ENV['EXCLUDE_TAGGED']
        next if tags.any? { |t| ENV['EXCLUDE_TAGGED'].split(/,\s?/).any? { |x| t == x } }
      end

      if ENV['INCLUDE_TAGGED']
        next unless tags.any? { |t| ENV['INCLUDE_TAGGED'].split(/,\s?/).any? { |x| t == x } }
      end

      post_filename = filename(post)
      # Next if we have a post in GitHub repo already
      next if repo_has_post?(github_repo, post_filename)

      markdown_files[post_filename] = Base64.encode64(render_template(post))
      wp_pids << post.id
    end

    # Add posts to repo in one commit
    add_files_to_repo(github_repo, markdown_files)
    # Remove Wordpress posts
    delete_wp_posts(wp_pids)

    "Sync'd Wordpress posts #{wp_pids.join(', ')} to GitHub #{github_repo}".green
  rescue RuntimeError => e
    raise "Error: #{e}".red
  end
end
