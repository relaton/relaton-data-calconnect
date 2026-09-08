# frozen_string_literal: true

source 'https://rubygems.org'

# The CalConnect flavor lives in the combined `relaton` gem now, not in a
# `relaton-calconnect` gem of its own. `crawler.rb`'s
# `require "relaton/calconnect/data_fetcher"` is the correct path there.
#
# Pin `main` explicitly rather than leaving `github:` unpinned: an unpinned
# source freezes whatever branch was current into `Gemfile.lock`, and relaton's
# remote churns transient feature branches, so a later `bundle update` can fail
# fetching a branch that has since been deleted.
gem 'relaton', git: 'https://github.com/relaton/relaton.git', branch: 'main'

# `build_index_v1.rb` needs no pubid, but the fetcher does once the CalConnect
# index-v2 producer lands: `Relaton::Calconnect` names
# `Pubid::Calconnect::Identifier` as the index `pubid_class:`, and that class
# exists only on pubid `main`.
#
# This repo has to pin pubid itself. Bundler reads a git gem's gemspec, never
# its Gemfile, so relaton's own pubid pin does not reach this bundle and the
# gemspec's `pubid ~> 2.0.0.pre.alpha.8` would be resolved instead.
# `Gemfile.lock` is git-ignored here, so CI resolves fresh on every crawl.
# Verify with `bundle list | grep pubid` before you trust a generated index.
gem 'pubid', git: 'https://github.com/pubid/pubid.git', branch: 'main'

group :development, :test do
  gem 'rspec', '~> 3.13'
end
