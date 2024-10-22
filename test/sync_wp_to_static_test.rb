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
require 'mocha/minitest'
require 'webmock/minitest'
require 'minitest/stub_const'
require './lib/sync_wp_to_static'

ENV['RACK_ENV'] ||= 'test'

# Test all the methods individually.
class SyncWpToStaticMethodsTest < Minitest::Test
  def setup
    ENV['GITHUB_REPOSITORY'] = 'lildude/lildude.github.io'
    ENV['INPUT_GITHUB_TOKEN'] = '0987654321'
    ENV['INPUT_POST_TEMPLATE'] = 'test/fixtures/template.erb'
    ENV['INPUT_POSTS_PATH'] = '_posts'
    ENV['INPUT_WORDPRESS_TOKEN'] = '1234567890'
    ENV['INPUT_WORDPRESS_ENDPOINT'] = 'https://public-api.wordpress.com/wp/v2/sites/fundiworks.wordpress.com'
  end

  def test_client
    assert_kind_of Octokit::Client, SyncWpToStatic.new.send(:client)
    assert_equal '0987654321', SyncWpToStatic.new.send(:client).access_token
  end

  def test_configured
    assert SyncWpToStatic.new.send(:configured?)

    ENV['INPUT_WORDPRESS_TOKEN'] = ''
    ENV['INPUT_GITHUB_TOKEN'] = nil

    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.send(:configured?) }
    assert_match "Whoops! Looks like you've not finished configuring things", exception.message
    assert_match 'wordpress_token', exception.message
    assert_match 'github_token', exception.message
  end

  def test_configured_include_and_exclude
    Object.stub_const(:ENV, ENV.to_hash.merge('INPUT_EXCLUDE_TAGGED' => 'foo', 'INPUT_INCLUDE_TAGGED' => 'bar')) do
      exception = assert_raises(RuntimeError) { SyncWpToStatic.new.send(:configured?) }
      assert_match "`exclude_tagged` and `include_tagged` can't both be set.", exception.message
    end
  end

  def test_template_found
    ENV['INPUT_POST_TEMPLATE'] = 'foobar.erb'

    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.send(:template_found?) }
    assert_match 'Whoops! foobar.erb not found.', exception.message
  end

  def test_wp_posts
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate([]), headers: {})
    assert_equal [], SyncWpToStatic.new.send(:wp_posts)

    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 404, body: JSON.generate(code: 'invalid_site', message: 'Invalid site specified', data: { status: 404 }))
      .to_raise(HTTParty::ResponseError.new(''))
    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.send(:wp_posts) }
    expected_message = <<~MSG.chomp
      Problem accessing #{ENV['INPUT_WORDPRESS_ENDPOINT']}/posts: Invalid site specified
    MSG
    assert_equal expected_message, exception.message
  end

  def test_parse_hashtags
    assert_equal %w[foo boo goo], SyncWpToStatic.new.send(:parse_hashtags, 'String #foo with #boo hash #goo tags.')
    assert_equal [], SyncWpToStatic.new.send(:parse_hashtags, 'String without hash tags.')
  end

  def test_filename
    faux_post = JSON.parse({ 'title' => { 'rendered' => '' }, 'date' => '2019-11-08T16:33:20' }.to_json, object_class: OpenStruct)
    assert_equal '2019-11-08-59600.md', SyncWpToStatic.new.send(:filename, faux_post)
    faux_post.title.rendered = 'Foo Bar gOO DaR'
    assert_equal '2019-11-08-foo-bar-goo-dar.md', SyncWpToStatic.new.send(:filename, faux_post)
  end

  def test_repo_has_post
    stub_request(:get, /api.github.com/)
      .to_return(
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(total_count: 1) },
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(total_count: 0)
      )
    assert SyncWpToStatic.new.send(:repo_has_post?, 'BAARFOOO')
    refute SyncWpToStatic.new.send(:repo_has_post?, 'FOOOBAAR')
  end

  def test_extract_images
    markdown_content = <<~END_OF_MARKDOWN
      ![alt](https://site.files.wordpress.com/2010/01/14/img.jpg?w=600;h=400)

      [![ano-alt](https://site.files.wordpress.com/2010/01/14/ano-img.jpg?w=600;h=400)](https://site.files.wordpress.com/2010/01/14/ano-img.jpg)

      Some test with a [link](https://example.com)
    END_OF_MARKDOWN

    expected = { 'img.jpg' => 'https://site.files.wordpress.com/2010/01/14/img.jpg', 'ano-img.jpg' => 'https://site.files.wordpress.com/2010/01/14/ano-img.jpg' }
    assert_equal expected, SyncWpToStatic.new.send(:extract_images, markdown_content)
  end

  def test_replace_images
    imgs = { 'img.jpg' => 'https://site.files.wordpress.com/2010/01/14/img.jpg', 'ano-img.jpg' => 'https://site.files.wordpress.com/2010/01/14/ano-img.jpg' }
    markdown_content = <<~END_OF_MARKDOWN2
      ![alt](https://site.files.wordpress.com/2010/01/14/img.jpg?w=600;h=400)

      [![ano-alt](https://site.files.wordpress.com/2010/01/14/ano-img.jpg?w=600;h=400)](https://site.files.wordpress.com/2010/01/14/ano-img.jpg)

      Some test with a [link](https://example.com)
    END_OF_MARKDOWN2

    expected = <<~END_OF_EXPECTED
      ![alt](/img/img.jpg)

      ![ano-alt](/img/ano-img.jpg)

      Some test with a [link](https://example.com)
    END_OF_EXPECTED

    ENV['INPUT_IMGS_PATH'] = 'img'
    assert_equal expected, SyncWpToStatic.new.send(:replace_images, markdown_content, imgs)
  end

  def test_download_and_encode_imgs
    imgs = { 'img.png' => 'https://site.files.wordpress.com/2010/01/14/img.png' }
    stub_request(:get, 'https://site.files.wordpress.com/2010/01/14/img.png')
      .to_return(status: 200, body: File.read(File.join(File.dirname(__FILE__), 'fixtures/img.png')))

    expected = { 'img/img.png' => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/TQBc\nNTh/AAAACklEQVR4nGNiAAAABgADNjd8qAAAAABJRU5ErkJggg==\n" }
    ENV['INPUT_IMGS_PATH'] = 'img'
    assert_equal expected, SyncWpToStatic.new.send(:download_and_encode_imgs, imgs)
  end

  def test_render_template
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
    assert_equal expected, SyncWpToStatic.new.send(:render_template, faux_post)

    faux_post.tags = %w[foo boo goo]
    faux_post.title.rendered = 'Title of my Cool Post'
    expected = File.read(File.join(File.dirname(__FILE__), 'fixtures/full_post.md'))
    assert_equal expected, SyncWpToStatic.new.send(:render_template, faux_post)

    faux_post.tags = []
    faux_post.content.rendered = '<p>Content with <strong>bold</strong> HTML and 😁 emoji.</p><p>Another line. #foo #boo #goo</p>'
    expected = File.read(File.join(File.dirname(__FILE__), 'fixtures/note_post_hashtags.md'))
    assert_equal expected, SyncWpToStatic.new.send(:render_template, faux_post)
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
    res = SyncWpToStatic.new.send(:add_files_to_repo, files)
    assert_equal res, 'Commit SHA: abc1234567890xyz'.yellow
  end

  def test_add_files_to_repo_dry_run
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

    Object.stub_const(:ENV, ENV.to_hash.merge('INPUT_DRY_RUN' => '1')) do
      res = SyncWpToStatic.new.send(:add_files_to_repo, files)
      assert_equal res, 'Would add _posts/2010-01-14-FOOOBAAR.md to lildude/lildude.github.io'.yellow
    end
  end

  def test_delete_wp_posts
    stub_request(:delete, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate(results: []), headers: {})
    assert_equal 'Wordpress posts deleted'.yellow, SyncWpToStatic.new.send(:delete_wp_posts, [11, 12, 13, 14])

    stub_request(:delete, /fundiworks.wordpress.com/)
      .to_return(status: 404, body: JSON.generate(
        code: 'rest_post_invalid_id', message: 'Invalid post ID.', data: { status: 404 }
      ))
      .to_raise(HTTParty::ResponseError.new(''))
    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.send(:delete_wp_posts, [11]) }
    expected_message = <<~MSG.chomp
      Problem deleting post: Invalid post ID.
    MSG
    assert_equal expected_message, exception.message
  end

  def test_delete_wp_posts_dry_run
    stub_request(:delete, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate(results: []), headers: {})

    Object.stub_const(:ENV, ENV.to_hash.merge('INPUT_DRY_RUN' => '1')) do
      assert output = SyncWpToStatic.new.send(:delete_wp_posts, [11, 12, 13, 14])
      assert_equal output, 'Would delete Wordpress posts 11, 12, 13, 14'.yellow
    end
  end

  def test_it_works
    obj = SyncWpToStatic.new
    assert obj
  end
end

# Test the run() method as a whole
class SyncWpToStaticRunTest < Minitest::Test
  def setup
    ENV['GITHUB_REPOSITORY'] = 'lildude/lildude.github.io'
    ENV['INPUT_GITHUB_TOKEN'] = '0987654321'
    ENV['INPUT_POST_TEMPLATE'] = 'test/fixtures/template.erb'
    ENV['INPUT_POSTS_PATH'] = '_posts'
    ENV['INPUT_WORDPRESS_TOKEN'] = '1234567890'
    ENV['INPUT_WORDPRESS_ENDPOINT'] = 'https://public-api.wordpress.com/wp/v2/sites/fundiworks.wordpress.com'

    @faux_posts = [
      {
        id: 101,
        title: { rendered: '' },
        tags: [],
        format: 'aside',
        type: 'post',
        date: '2019-11-08T16:33:20',
        content: { rendered: 'Post content #run #fooBar' }
      },
      {
        id: 102,
        title: { rendered: 'This is a fantastic title' },
        tags: %w[tag1 tag2],
        format: 'post',
        type: 'post',
        date: '2019-11-09T15:31:19',
        content: { rendered: 'Post content with tags and title.' }
      },
      {
        id: 103,
        title: { rendered: 'This is a fantastic title too' },
        tags: %w[tag1 tech],
        format: 'post',
        type: 'post',
        date: '2019-11-09T15:31:19',
        content: { rendered: 'Post content with tags and title.' }
      },
      {
        id: 104,
        title: { rendered: 'This is a fantastic title too' },
        tags: %w[],
        format: 'post',
        type: 'post',
        date: '2019-11-09T15:31:19',
        content: {
          rendered:
          '<p>Post content with an image <a href="http://example.com/file/img.jpg"><img alt="img alt" src="http://example.com/file/img.jpg?w=600&h=600">.</p>'
        }
      }
    ]
  end

  def test_run_runtime_error
    ENV['INPUT_WORDPRESS_TOKEN'] = nil
    exception = assert_raises(RuntimeError) { SyncWpToStatic.new.run }
    assert_match 'Whoops! Looks like you\'ve not finished configuring things.', exception.message
  end

  def test_run_no_posts
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate([]), headers: {})

    assert_equal 'Nothing new'.blue, SyncWpToStatic.new.run
  end

  def test_run_all_the_types_of_posts
    # Stub getting WP posts
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate(@faux_posts), headers: {})
    # Stub checking for posts in repo - the repo has the first post, but not the subsequent.
    stub_request(:get, /api.github.com/)
      .to_return(
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(total_count: 1) },
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(total_count: 0)
      )
    stub_request(:get, 'http://example.com/file/img.jpg')
      .to_return(status: 200, body: 'pretend_img_bin_data')
    # Stub add_files_to_repo and delete_wp_posts - we test these above so don't care about their behaviour right now
    runit = SyncWpToStatic.new
    runit.expects(:add_files_to_repo).returns
    runit.expects(:delete_wp_posts).returns
    expected = "Sync'd Wordpress posts 102, 103, 104 to GitHub lildude/lildude.github.io".green
    assert_equal expected, runit.run
  end

  def test_sync_only_included
    # Stub getting WP posts
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate(@faux_posts), headers: {})
    # Stub checking for posts in repo - the repo has the first post, but not the subsequent.
    stub_request(:get, /api.github.com/)
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(total_count: 0)
      )
    # Stub add_files_to_repo and delete_wp_posts (and ENV) - we test these above so don't care about their behaviour right now
    Object.stub_const(:ENV, ENV.to_hash.merge('INPUT_INCLUDE_TAGGED' => 'run')) do
      runit = SyncWpToStatic.new
      runit.expects(:add_files_to_repo).returns
      runit.expects(:delete_wp_posts).returns
      expected = "Sync'd Wordpress posts 101 to GitHub lildude/lildude.github.io".green
      assert_equal expected, runit.run
    end
  end

  def test_dont_sync_excluded
    # Stub getting WP posts
    stub_request(:get, /fundiworks.wordpress.com/)
      .to_return(status: 200, body: JSON.generate(@faux_posts), headers: {})
    # Stub checking for posts in repo - the repo has the first post, but not the subsequent.
    stub_request(:get, /api.github.com/)
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(total_count: 0)
      )
    stub_request(:get, 'http://example.com/file/img.jpg')
      .to_return(status: 200, body: 'pretend_img_bin_data')
    # Stub add_files_to_repo and delete_wp_posts (and ENV) - we test these above so don't care about their behaviour right now
    Object.stub_const(:ENV, ENV.to_hash.merge('INPUT_EXCLUDE_TAGGED' => 'run, tech')) do
      runit = SyncWpToStatic.new
      runit.expects(:add_files_to_repo).returns
      runit.expects(:delete_wp_posts).returns
      expected = "Sync'd Wordpress posts 102, 104 to GitHub lildude/lildude.github.io".green
      assert_equal expected, runit.run
    end
  end
end
