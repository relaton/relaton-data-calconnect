# frozen_string_literal: true

require "date"
require "yaml"

require "relaton/index"

#
# The legacy `index-v1`, built from the documents the crawl wrote.
#
# `Relaton::Calconnect::DataFetcher` is migrating to a pubid-backed `index-v2`:
# its rows become `Pubid::Calconnect::Identifier` objects serialized to a
# `_type: pubid:calconnect:*` hash, and it stops writing `index-v1` itself.
# Released relaton v2 consumers still fetch `index-v1.zip` from this repository,
# so this repository has to keep producing it.
#
# The migration has NOT landed on relaton `main`, which the Gemfile pins:
# `Relaton::Calconnect::INDEXFILE` is still `index-v1` there, and the fetcher
# still writes that file itself, mid-`fetch`. That is harmless, and needs no
# guard here, because `crawler.rb` runs this afterwards and it overwrites the
# whole file from `data/` either way.
#
# It is built from `data/`, and NOT derived from `index-v2` the way
# relaton-data-ecma, -w3c, -iana and -bipm derive theirs. CalConnect can do
# this, and they cannot, because a v1 row id here is the document's own printed
# docidentifier -- a bare string, with no edition and no volume to split out.
# Reading it back from the document buys three things:
#
#   * `index-v1` never depends on pubid. A renderer change cannot silently
#     rewrite the file every released v2 consumer reads.
#   * A document whose id pubid cannot parse is skipped from `index-v2` by the
#     fetcher, but keeps its `index-v1` row rather than disappearing.
#   * It is correct against an installed relaton that still writes `index-v1`
#     itself, so it needs no `INDEXFILE` guard.
#
# Nothing here zips. relaton/support's shared `crawler.yml` zips every
# `index*.yaml` that changed and commits the yaml and the zip together.
#
module IndexV1
  FILE = "index-v1.yaml"

  # Where `Relaton::Calconnect::DataFetcher` writes the crawled documents.
  DATA_DIR = "data"

  # A pool key of its own, so these plain string rows never land in the
  # pubid-typed `:CC` pool the fetcher fills.
  POOL_KEY = :CC_V1

  class << self
    #
    # Write `index-v1.yaml` from the documents the crawl just wrote.
    #
    # Declines unless there is a real corpus to index; see {.source}.
    #
    # @return [Integer, nil] rows written, or nil if it declined
    #
    def write
      rows = source or return nil

      index = Relaton::Index.find_or_create(POOL_KEY, file: FILE)
      # Build from scratch, and never merge. Nothing clears `index-v1.yaml`
      # before a crawl -- `crawler.rb` deliberately leaves the published file
      # alone -- so without this, `index` lazily reads the committed file back
      # and `add_or_update` merges this crawl's rows into the last one's,
      # keeping documents that upstream has since dropped. `remove_all` sets
      # the rows to `[]` without reading the file at all.
      index.remove_all
      rows.each { |id, file| index.add_or_update id, file }
      index.save

      written = index.index.size
      if written < rows.size
        Relaton::Index::Util.warn "#{rows.size - written} of #{rows.size} " \
                                  "documents share an id with another and " \
                                  "collapsed into one index-v1 row"
      end
      written
    end

    #
    # The primary docidentifier of one crawled document.
    #
    # `primary: true` is the key the fetcher itself indexed on. The fallback to
    # the first entry covers a document the model wrote without the flag; the
    # published corpus carries exactly one docidentifier per document today.
    #
    # @param [String] file path to a crawled document
    #
    # @return [String, nil] the printed id, or nil if the document carries none
    #
    def primary_docid(file)
      doc = YAML.safe_load File.read(file), permitted_classes: [Date, Time],
                                            aliases: true
      return nil unless doc.is_a? Hash

      ids = doc["docidentifier"] || []
      id = ids.find { |i| i["primary"] } || ids.first
      id && id["content"]
    end

    private

    #
    # The `[id, file]` pairs to index, or nil to decline.
    #
    # Indexing an empty corpus is destructive, not merely useless: a crawl that
    # wrote no document -- a wiped `data/`, a fetch that failed -- would
    # otherwise replace the published `index-v1.yaml` with `--- []`. Declining
    # leaves the last good file in place, and `crawler.rb` turns the nil into a
    # failed job so the empty crawl is seen.
    #
    # Sorted by path, because `Relaton::Index` re-sorts only a pubid-typed
    # index and takes the insertion order otherwise. A stable order keeps a
    # crawl's diff down to the rows that really changed.
    #
    # @return [Array<Array(String, String)>, nil] id/file pairs, or nil
    #
    def source
      rows = Dir[File.join(DATA_DIR, "*.yaml")].sort.filter_map do |file|
        id = primary_docid file
        # The document is already on disk; only the index row is lost. Report
        # it rather than indexing nil, which every consumer would then read.
        unless id
          Relaton::Index::Util.warn "No docidentifier in `#{file}`; " \
                                    "it is not in index-v1"
          next
        end
        [id, file]
      end
      rows.empty? ? nil : rows
    end
  end
end
