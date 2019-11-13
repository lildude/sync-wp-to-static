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
