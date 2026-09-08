# frozen_string_literal: true

# `crawler.rb` deletes `data/` on load, so it cannot be required. Read it as
# source text instead, the way relaton-data-ecma, relaton-data-iana and
# relaton-data-bipm guard their own crawlers.
RSpec.describe "crawler.rb" do
  # Comments stripped: this file talks about `IndexV1.write` and about the
  # globs it must not use, so a scan over the raw text matches its own prose.
  let(:source) do
    File.read(File.join(REPO_ROOT, "crawler.rb"))
        .lines.reject { |line| line.strip.start_with? "#" }.join
  end
  let(:globs) { source.scan(/Dir\.glob\(["']([^"']+)["']\)/).flatten }

  # A bare `index*` glob also matches a Ruby file named index*.rb beside it, and
  # the crawler would delete the very source it requires. relaton-data-bipm hit
  # this exact bug. Guard the names a future session is most likely to add, not
  # only the one here today.
  it "deletes no Ruby source beside the generated index files" do
    expect(globs).not_to be_empty
    %w[build_index_v1.rb derive_index_v1.rb index_builder.rb crawler.rb]
      .each do |ruby|
      globs.each do |glob|
        expect(File.fnmatch(glob, ruby, File::FNM_EXTGLOB))
          .to be(false), "glob #{glob.inspect} matches #{ruby}"
      end
    end
  end

  # The fetcher merges into the index it loads, so a stale index-v2 would keep
  # documents that upstream dropped.
  it "clears index-v2 before a forced re-crawl" do
    %w[index-v2.yaml index-v2.zip].each do |file|
      expect(globs.any? { |g| File.fnmatch(g, file, File::FNM_EXTGLOB) })
        .to be(true), "no glob matches #{file}"
    end
  end

  # The data-loss guard. `IndexV1.write` rebuilds from scratch, so pre-deleting
  # index-v1 gains nothing -- and a `--force` run whose scrape then fails
  # entirely would leave the published file deleted, with the rebuild correctly
  # declining to replace it.
  it "never deletes the published index-v1" do
    %w[index-v1.yaml index-v1.zip].each do |file|
      expect(globs.any? { |g| File.fnmatch(g, file, File::FNM_EXTGLOB) })
        .to be(false), "a glob deletes #{file}"
    end
  end

  # Order is the contract: `IndexV1.write` reads the `data/` the fetch wrote.
  # Run first, it would find the previous crawl's documents, or none at all.
  it "builds index-v1 after the fetch" do
    fetch = source.index("Relaton::Calconnect::DataFetcher.fetch")
    build = source.index("IndexV1.write")
    expect(fetch).not_to be_nil
    expect(build).not_to be_nil
    expect(build).to be > fetch
  end

  # `DataFetcher#fetch` swallows every per-document scrape error and never
  # raises, even when every document fails. A declined rebuild is the only
  # signal that the crawl produced nothing, so the job has to fail on it --
  # otherwise CI commits a half-empty tree. Source text is the only way to
  # check this: the file cannot be loaded.
  it "fails the crawl when the rebuild declines" do
    line = source.lines.find { |l| l.include? "IndexV1.write" }
    expect(line).to match(/\babort\b/)
  end
end
