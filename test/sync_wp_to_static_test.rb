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
require 'mocha/mini_test'
require 'webmock/minitest'
require './lib/sync_wp_to_static'

ENV['RACK_ENV'] ||= 'test'

class SyncWpToStaticMethodsTest < Minitest::Test
  def setup
    ENV['GITHUB_TOKEN'] = '0987654321'
    ENV['GITHUB_REPO'] = 'lildude/lildude.github.io'
    ENV['WORDPRESS_TOKEN'] = '1234567890'
    ENV['WORDPRESS_ENDPOINT'] = 'https://public-api.wordpress.com/wp/v2/sites/fundiworks.wordpress.com'
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
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate([]), headers: {})
    assert_equal [], SyncWpToStatic.new.wp_posts

    stub_request(:get, /fundiworks.wordpress.com/)
      .to_raise(HTTParty::ResponseError.new('404 Not Found'))
    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.wp_posts }
    expected_message = <<~MSG.chomp
      Problem accessing #{ENV['WORDPRESS_ENDPOINT']}/posts: 404 Not Found
    MSG
    assert_equal expected_message, exception.message
  end

  def test_parse_hashtags
    assert_equal %w[foo boo goo], SyncWpToStatic.new.parse_hashtags('String #foo with #boo hash #goo tags.')
    assert_equal [], SyncWpToStatic.new.parse_hashtags('String without hash tags.')
  end

  def test_filename
    faux_post = JSON.parse({ 'title' => { 'rendered' => '' }, 'date' => '2019-11-08T16:33:20' }.to_json, object_class: OpenStruct)
    assert_equal '59600.md', SyncWpToStatic.new.filename(faux_post)
    faux_post.title.rendered = 'Foo Bar gOO DaR'
    assert_equal '2019-11-08-foo-bar-goo-dar.md', SyncWpToStatic.new.filename(faux_post)
  end

  def test_repo_has_post
    stub_request(:get, /api.github.com/)
      .to_return(
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(total_count: 1) },
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(total_count: 0)
      )
    assert SyncWpToStatic.new.repo_has_post?('lildude/lildude.github.io', 'BAARFOOO')
    refute SyncWpToStatic.new.repo_has_post?('lildude/lildude.github.io', 'FOOOBAAR')
  end

  def test_markdown_content
    faux_post = JSON.parse(
      {
        title: { rendered: '' },
        date: '2019-11-08T16:33:20',
        tags: [],
        format: 'aside',
        type: 'post',
        content: { rendered: '<p>Content with <strong>bold</strong> HTML and 😁 emoji.</p><p>Another line.</p>' }
      }.to_json, object_class: OpenStruct
    )

    expected = File.read(File.join(File.dirname(__FILE__), 'fixtures/note_post_no_tags.md'))
    assert_equal expected, SyncWpToStatic.new.markdown_content(faux_post)

    faux_post.tags = %w[foo boo goo]
    faux_post.title.rendered = 'Title of my Cool Post'

    expected = File.read(File.join(File.dirname(__FILE__), 'fixtures/full_post.md'))
    assert_equal expected, SyncWpToStatic.new.markdown_content(faux_post)
  end

  def test_add_files_to_repo
    stub_request(:any, /api.github.com/)
      .to_return(
        { status: 200, headers: { 'Content-Type' => 'application/json' }, # Stub ref
          body: JSON.generate(object: { sha: 'abc1234567890xyz' }) },
        { status: 200, headers: { 'Content-Type' => 'application/json' }, # Stub commit
          body: JSON.generate(commit: { tree: { sha: 'abc1234567890xyz' } }) },
        { status: 200, headers: { 'Content-Type' => 'application/json' }, # Stub create_tree
          body: JSON.generate(sha: 'abc1234567890xyz') },
        { status: 200, headers: { 'Content-Type' => 'application/json' }, # Stub commit_commit
          body: JSON.generate(sha: 'abc1234567890xyz') },
        status: 200, headers: { 'Content-Type' => 'application/json' }, # Stub update_ref
        body: JSON.generate(
          url: 'https://api.github.com/repos/lildude.github.io/git/refs/heads/master',
          object: { sha: 'abc1234567890xyz' }
        )
      )

    files = {
      '_posts/2010-01-14-FOOOBAAR.md': 'TVkgU0VDUkVUIEhBUyBCRUVOIFJFVkVBTEVEIPCfmJw='
    }
    assert res = SyncWpToStatic.new.add_files_to_repo('lildude/lildude.github.io', files)
    assert_equal res['object']['sha'], 'abc1234567890xyz'
  end

  def test_delete_wp_posts
    stub_request(:delete, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate(results: []), headers: {})
    assert SyncWpToStatic.new.delete_wp_posts([11, 12, 13, 14])

    stub_request(:delete, /fundiworks.wordpress.com/)
      .to_raise(HTTParty::ResponseError.new('404 Not Found'))
    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.delete_wp_posts([11]) }
    expected_message = <<~MSG.chomp
      Problem deleting post: Code 404 - Not found
    MSG
    assert_equal expected_message, exception.message
  end

  def test_it_works
    obj = SyncWpToStatic.new
    assert obj
  end
end

class SyncWpToStaticRunTest < Minitest::Test
  def setup
    ENV['GITHUB_TOKEN'] = '0987654321'
    ENV['WORDPRESS_TOKEN'] = '1234567890'
    ENV['WORDPRESS_ENDPOINT'] = 'https://public-api.wordpress.com/wp/v2/sites/fundiworks.wordpress.com'
  end

  def test_run_no_posts
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate([]), headers: {})

    assert_equal 'Nothing new'.blue, SyncWpToStatic.new.run
  end

  def test_run_all_the_types_of_posts
    faux_posts = [
    {
      id: 101,
      title: { rendered: '' },
      tags: [],
      format: 'aside',
      type: 'post',
      date: '2019-11-08T16:33:20',
        content: { rendered: 'Post content #run' }
    },
    {
      id: 102,
      title: { rendered: 'This is a fantastic title' },
        tags: %w[tag1 tag2],
      format: 'post',
      type: 'post',
      date: '2019-11-09T15:31:19',
        content: { rendered: 'Post content with tags and title.' }
      }
    ]
    # Stub getting WP posts
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate(faux_posts), headers: {})
    # Stub checking for posts in repo - the repo has the first post, but not the subsequent.
    stub_request(:get, /api.github.com/)
      .to_return(
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(total_count: 1) },
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(total_count: 0)
      )
    # Stub add_files_to_repo and delete_wp_posts - we test these above so don't care about their behaviour right now
    runit = SyncWpToStatic.new
    runit.expects(:add_files_to_repo).returns
    runit.expects(:delete_wp_posts).returns
    expected = "Sync'd Wordpress posts 102 to GitHub lildude/lildude.github.io".green
    assert_equal expected, runit.run
  end
end
