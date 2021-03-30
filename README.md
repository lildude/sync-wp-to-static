# Sync Wordpress Posts to Static GitHub Repo

This GitHub Action syncs posts from a Wordpress site to a static site's GitHub repo using a user-provided template.

## Inputs

### `github_token`

**Required** The GitHub token required to access the repository. This will almost always be set to [`${{ secrets.GITHUB_TOKEN }}`](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/authenticating-with-the-github_token#using-the-github_token-in-a-workflow).

### `post_template`

**Required** Path within the repository to the ERB template that will used to generate the posts in the GitHub repository.

### `posts_path`

**Required** Relative path to the directory into which the posts should be added, for example `_posts` for Jeklly, or `content/posts` for Hugo.

### `wordpress_endpoint`

**Required** URL to the Wordpress V2 endpoint for the Wordpress blog you would like to synchronise with.

### `wordpress_token`

**Required** OAuth token used to delete posts from the Wordpress blog. Use an [encrypted secret for this](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets).

### `dont_delete`

Boolean. Delete Wordpress posts after synchronisation.

### `dry_run`

Boolean. Perform the action but do not make any changes. This will show messages in the logs detailing the posts that would be synchronised and deleted.

### `exclude_tagged`

Comma-separated list of tags that should not be synchronised. Do not set if setting `include_tagged`.

### `include_tagged`

Comma-separated list of tags that should be synchronised. Only posts with these tags will be synchronised. Do not set if setting `exclude_tagged`.


## Example Usage

```yaml
name: Sync WP to Static

on:
  schedule:
    - cron:  '13 * * * *'

jobs:
sync_wp_to_static:
  runs-on: ubuntu-latest
  name: Sync WP to sync_wp_to_static
  steps:
    - name: Checkout
      uses: actions/checkout@v1
    - name: Sync Posts
      uses: lildude/sync-wp-to-static@v1
      env:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        post_template: template.erb
        posts_path: _posts
        wordpress_endpoint: https://public-api.wordpress.com/wp/v2/sites/example.wordpress.com
        wordpress_token: ${{ secrets.wordpress_token }}
        include_tagged: 'foo, bar'
        dont_delete: true
```

