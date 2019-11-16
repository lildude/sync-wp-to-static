# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'

task default: 'test'

# rake test
Rake::TestTask.new do |task|
  task.pattern = 'test/*_test.rb'
  task.warning = false
end

# rake rubocop
RuboCop::RakeTask.new

# rake console
task :console do
  require 'pry'
  require './lib/sync_wp_to_static'

  def reload!
    files = $LOADED_FEATURES.select { |feat| feat =~ %r{./lib/sync_wp_to_static} }
    files.each { |file| load file }
  end

  ARGV.clear
  Pry.start
end
