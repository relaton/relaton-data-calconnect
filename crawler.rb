# frozen_string_literal: true

require 'fileutils'
require 'relaton/calconnect/data_fetcher'

# Pass --force (e.g. via the workflow_dispatch "force" input) to wipe the
# existing data/ + index files and re-download every document from upstream.
# On a normal run the fetcher returns 304 Not Modified when upstream hasn't
# changed and leaves the tree alone.
if ARGV.include?('--force')
  FileUtils.rm_rf('data')
  FileUtils.rm_f(Dir.glob('index*'))
end

Relaton::Calconnect::DataFetcher.fetch
