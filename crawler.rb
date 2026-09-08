# frozen_string_literal: true

require 'fileutils'
require 'relaton/calconnect/data_fetcher'
require_relative 'build_index_v1'

# Pass --force (e.g. via the workflow_dispatch "force" input) to wipe the
# existing data/ + index files and re-download every document from upstream.
# On a normal run the fetcher returns 304 Not Modified when upstream hasn't
# changed and leaves the tree alone.
if ARGV.include?('--force')
  FileUtils.rm_rf('data')
  # index-v2 only, for two separate reasons.
  #
  # Narrower than 'index*', which would also match a Ruby file named index*.rb
  # next to it -- the crawler would then delete its own source.
  # relaton-data-bipm hit that bug; spec/crawler_sources_spec.rb guards it here.
  #
  # And index-v1 is deliberately NOT pre-deleted. The fetcher MERGES into the
  # index it loads, so a stale index-v2 would keep documents upstream dropped;
  # `IndexV1.write` instead rebuilds from scratch, so pre-deleting index-v1
  # gains nothing and costs the published file if the rebuild then declines.
  FileUtils.rm_f(Dir.glob('index-v2.{yaml,zip}'))
end

Relaton::Calconnect::DataFetcher.fetch

# Released relaton v2 consumers still read index-v1.zip from this branch, so
# rebuild it from the documents the fetch just wrote; see build_index_v1.rb.
#
# A nil return means data/ held no document to index. The fetcher swallows every
# per-document scrape error and never raises, so that is the one signal a crawl
# produced nothing -- fail the job rather than let CI commit a half-empty tree.
IndexV1.write or abort 'crawler: no document to index; index-v1 was not rebuilt'
