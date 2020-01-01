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
  def initialize
    @dont_delete = ENV['INPUT_DONT_DELETE']
    @dry_run = ENV['INPUT_DRY_RUN']
    @excluded_tags = ENV['INPUT_EXCLUDE_TAGGED']
    @github_repo = ENV['GITHUB_REPOSITORY']
    @github_token = ENV['INPUT_GITHUB_TOKEN']
    @included_tags = ENV['INPUT_INCLUDE_TAGGED']
    @post_template = ENV['INPUT_POST_TEMPLATE']
    @posts_path = ENV['INPUT_POSTS_PATH']
    @wordpress_endpoint = ENV['INPUT_WORDPRESS_ENDPOINT']
    @wordpress_token = ENV['INPUT_WORDPRESS_TOKEN']
  end

  def run
    # Check we been configured
    configured?
    # Check we can find the template file
    template_found?
    # Get all Wordpress posts - assumes there aren't many so we don't bother with paging
    return 'Nothing new'.blue if wp_posts.empty?

    markdown_files = {}
    wp_pids = []
    wp_posts.each do |post|
      next unless include_post?(post)

      post_filename = filename(post)
      # Next if we have a post in GitHub repo already
      next if repo_has_post?(post_filename)

      markdown_files[post_filename] = Base64.encode64(render_template(post))
      wp_pids << post.id
    end

    return 'Nothing to post'.blue if markdown_files.empty?

    # Add posts to repo in one commit
    out = [] << add_files_to_repo(markdown_files).to_s
    # Remove Wordpress posts
    out << delete_wp_posts(wp_pids).to_s
    out << "Sync'd Wordpress posts #{wp_pids.join(', ')} to GitHub #{@github_repo}".green
    out.reject(&:empty?).join("\n")
  end

  private

  def client
    @client ||= Octokit::Client.new(access_token: @github_token)
  end

  def configured?
    missing_inputs = []
    %w[GITHUB_TOKEN POSTS_PATH POST_TEMPLATE WORDPRESS_ENDPOINT WORDPRESS_TOKEN].each do |env_var|
      missing_inputs << env_var unless ENV["INPUT_#{env_var}"] && !ENV["INPUT_#{env_var}"].empty?
    end

    msg = <<~ERROR_MSG
      Whoops! Looks like you've not finished configuring things.
      Missing or empty inputs: #{missing_inputs.join(', ').downcase}."
    ERROR_MSG

    raise msg unless missing_inputs.empty?

    # Include and exclude both can't be set at the same time
    raise "`exclude_tagged` and `include_tagged` can't both be set." if ENV['INPUT_EXCLUDE_TAGGED'] && ENV['INPUT_INCLUDE_TAGGED']

    true
  end

  def template_found?
    raise "Whoops! #{@post_template} not found." unless File.exist?(@post_template)
  end

  def wp_posts
    @wp_posts ||=
      begin
        uri = "#{@wordpress_endpoint}/posts"
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
    rendered_title = post.title.rendered
    fn =
      if rendered_title.empty?
        date.strftime('%s').to_i % (24 * 60 * 60)
      else
        slug = rendered_title.downcase.gsub('/[\s.\/_]/', ' ').gsub(/[^\w\s-]/, '').squeeze(' ').tr(' ', '-').chomp('-')
        "#{date.strftime('%F')}-#{slug}"
      end

    "#{fn}.md"
  end

  def repo_has_post?(filename)
    res = client.search_code("filename:#{filename} repo:#{@github_repo} path:#{@posts_path}")
    return false if res.total_count.zero?

    true
  end

  def render_template(post)
    render_binding = binding
    content = post.content.rendered
    post.tags = parse_hashtags(content) if post.tags.empty?
    content = ReverseMarkdown.convert(content.gsub(/#\w+/, '')) # rubocop:disable Lint/UselessAssignment
    template = File.read(@post_template)

    ERB.new(template, trim_mode: '-').result(render_binding)
  end

  def add_files_to_repo(files = {})
    return "Would add #{files.keys.join(', ')} to #{@github_repo}".yellow if @dry_run

    latest_commit_sha = client.ref(@github_repo, 'heads/master').object.sha
    base_tree_sha = client.commit(@github_repo, latest_commit_sha).commit.tree.sha

    new_tree = files.map do |path, content|
      Hash(
        path: "#{@posts_path}/#{path}",
        mode: '100644',
        type: 'blob',
        sha: client.create_blob(@github_repo, content, 'base64')
      )
    end

    new_tree_sha = client.create_tree(@github_repo, new_tree, base_tree: base_tree_sha).sha
    new_commit_sha = client.create_commit(@github_repo, 'New WP sync\'d post', new_tree_sha, latest_commit_sha).sha
    res = client.update_ref(@github_repo, 'heads/master', new_commit_sha)
    "Commit SHA: #{res['object']['sha']}".yellow
  end

  def delete_wp_posts(post_ids)
    return if @dont_delete
    return "Would delete Wordpress posts #{post_ids.join(', ')}".yellow if @dry_run

    headers = { 'Authorization': "Bearer #{@wordpress_token}" }
    post_ids.each do |pid|
      uri = "#{@wordpress_endpoint}/posts/#{pid}"
      HTTParty.delete(uri, headers: headers, raise_on: [403, 404, 500])
    end
    'Wordpress posts deleted'.yellow
  rescue HTTParty::ResponseError => e
    body = JSON.parse(e.response.body, object_class: OpenStruct)
    raise "Problem deleting post: #{body.message}"
  end

  def include_post?(post)
    tags = Set.new(post.tags) + parse_hashtags(post.content.rendered)
    return false if tags.empty? && @included_tags

    ok = true
    tags.any? do |tag|
      if @excluded_tags
        ok = false if @excluded_tags.split(/,\s?/).any? { |excluded| tag == excluded }
      end
      if @included_tags
        ok = false unless @included_tags.split(/,\s?/).any? { |included| tag == included }
      end
    end

    ok
  end
end
