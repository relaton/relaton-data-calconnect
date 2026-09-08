# frozen_string_literal: true

RSpec.describe IndexV1 do
  # A minimal crawled document: `index-v1` reads nothing but the primary
  # docidentifier, so nothing else has to be realistic.
  def document(docidentifier)
    { "id" => "CCX", "docidentifier" => docidentifier }.to_yaml
  end

  def write_doc(name, docidentifier)
    FileUtils.mkdir_p IndexV1::DATA_DIR
    File.write File.join(IndexV1::DATA_DIR, name), document(docidentifier)
  end

  describe ".primary_docid" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    it "reads the content of the only docidentifier" do
      write_doc "a.yaml", [{ "content" => "CC 18011:2018", "primary" => true }]

      expect(described_class.primary_docid("data/a.yaml"))
        .to eq "CC 18011:2018"
    end

    # The crawled corpus carries one docidentifier per document today, but the
    # model allows several. `primary: true` is what the old fetcher keyed on.
    it "picks the primary entry when several are present" do
      write_doc "a.yaml", [{ "content" => "urn:cc:18011" },
                           { "content" => "CC 18011:2018", "primary" => true }]

      expect(described_class.primary_docid("data/a.yaml"))
        .to eq "CC 18011:2018"
    end

    it "falls back to the first entry when none is marked primary" do
      write_doc "a.yaml", [{ "content" => "CC 18011:2018" },
                           { "content" => "urn:cc:18011" }]

      expect(described_class.primary_docid("data/a.yaml"))
        .to eq "CC 18011:2018"
    end

    it "returns nil when the document carries no docidentifier" do
      write_doc "a.yaml", []

      expect(described_class.primary_docid("data/a.yaml")).to be_nil
    end
  end

  describe ".write" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    def rows
      YAML.safe_load File.read(IndexV1::FILE), permitted_classes: [Symbol]
    end

    it "writes one row per crawled document" do
      write_doc "cc-18011-2018.yaml",
                [{ "content" => "CC 18011:2018", "primary" => true }]
      write_doc "cc-s-0601-2005.yaml",
                [{ "content" => "CC/S 0601:2005", "primary" => true }]

      expect(described_class.write).to eq 2
      expect(rows).to contain_exactly(
        { id: "CC 18011:2018", file: "data/cc-18011-2018.yaml" },
        { id: "CC/S 0601:2005", file: "data/cc-s-0601-2005.yaml" },
      )
    end

    # The id is the document's own printed form, stored as a plain String.
    # `Relaton::Index` writes a Hash id for a pubid-typed index; a released
    # relaton v2 consumer reads this one as a String and would reject a Hash.
    it "stores the id as a plain string" do
      write_doc "a.yaml", [{ "content" => "CC/A 0001:2000", "primary" => true }]

      described_class.write
      expect(rows.first[:id]).to be_a String
    end

    # Insertion order is the file order, because `Relaton::Index` re-sorts only
    # a pubid-typed index. Sorting by path keeps the published file stable from
    # one crawl to the next, so a diff shows real changes only.
    it "orders the rows by file path" do
      %w[c.yaml a.yaml b.yaml].each do |name|
        write_doc name, [{ "content" => "CC #{name}", "primary" => true }]
      end

      described_class.write
      expect(rows.map { |r| r[:file] })
        .to eq %w[data/a.yaml data/b.yaml data/c.yaml]
    end

    # Nothing clears `index-v1.yaml` before a crawl, so without `remove_all` the
    # Type reads the committed file back and this crawl's rows merge into the
    # last crawl's, keeping documents upstream has since dropped.
    it "rebuilds from scratch rather than merging into a pooled index" do
      write_doc "a.yaml", [{ "content" => "CC A", "primary" => true }]
      described_class.write
      FileUtils.rm_f Dir.glob("data/*.yaml")
      write_doc "b.yaml", [{ "content" => "CC B", "primary" => true }]

      expect(described_class.write).to eq 1
      expect(rows.map { |r| r[:file] }).to eq ["data/b.yaml"]
    end

    # The same merge, through the other door. `crawler.rb` no longer deletes
    # index-v1.yaml, so a Type created fresh -- a new crawl process -- reads the
    # committed file back. `remove_all` has to beat that read too.
    it "rebuilds from scratch rather than merging the committed file" do
      File.write IndexV1::FILE,
                 [{ id: "CC GONE", file: "data/gone.yaml" }].to_yaml
      Relaton::Index.close IndexV1::POOL_KEY
      write_doc "a.yaml", [{ "content" => "CC A", "primary" => true }]

      expect(described_class.write).to eq 1
      expect(rows.map { |r| r[:file] }).to eq ["data/a.yaml"]
    end

    # The document is already on disk, and it is the crawl's job to report an
    # id it could not build. Indexing nil would break every consumer instead.
    it "skips a document that carries no docidentifier" do
      write_doc "a.yaml", [{ "content" => "CC A", "primary" => true }]
      write_doc "b.yaml", []

      expect(described_class.write).to eq 1
      expect(rows.map { |r| r[:file] }).to eq ["data/a.yaml"]
    end

    # The guard. A build that ran on an empty corpus would write `--- []` over
    # the index every released relaton v2 consumer reads.
    it "declines, and writes nothing, when data/ is absent" do
      expect(described_class.write).to be_nil
      expect(File).not_to exist(IndexV1::FILE)
    end

    it "declines when data/ holds no documents" do
      FileUtils.mkdir_p IndexV1::DATA_DIR

      expect(described_class.write).to be_nil
      expect(File).not_to exist(IndexV1::FILE)
    end

    it "declines when no document yields a docidentifier" do
      write_doc "a.yaml", []

      expect(described_class.write).to be_nil
      expect(File).not_to exist(IndexV1::FILE)
    end

    # Two documents can only collapse into one row by sharing an id, which the
    # published corpus never does. The count is the tripwire for that.
    it "reports the row count that actually reached the index" do
      write_doc "a.yaml", [{ "content" => "CC A", "primary" => true }]
      write_doc "b.yaml", [{ "content" => "CC A", "primary" => true }]

      expect(described_class.write).to eq 1
    end
  end

  # The acceptance test. Rebuild the whole index from the committed corpus and
  # require the result to be the committed `index-v1.yaml` row set. Nothing
  # smaller proves that every published row survives the rebuild.
  describe "the published corpus" do
    around do |example|
      Dir.mktmpdir do |dir|
        # Symlink rather than copy: the example only reads the documents.
        FileUtils.ln_s File.join(REPO_ROOT, IndexV1::DATA_DIR),
                       File.join(dir, IndexV1::DATA_DIR)
        Dir.chdir(dir) { example.run }
      end
    end

    let(:published) do
      YAML.safe_load File.read(File.join(REPO_ROOT, IndexV1::FILE)),
                     permitted_classes: [Symbol]
    end

    let(:rebuilt) do
      described_class.write
      YAML.safe_load File.read(IndexV1::FILE), permitted_classes: [Symbol]
    end

    it "rebuilds every published row unchanged" do
      # Sorted rather than `contain_exactly`, which compares 191 rows pairwise
      # and reports an unreadable diff on failure.
      by_file = ->(index) { index.sort_by { |row| row[:file] } }
      expect(by_file.call(rebuilt)).to eq by_file.call(published)
    end

    it "keeps every published row" do
      # Not a hardcoded count: a crawl commits a new corpus regularly. The floor
      # is the size the corpus had when this was written, so a gross truncation
      # still fails rather than passing against a truncated published file.
      expect(published.size).to be >= 188
      expect(rebuilt.size).to eq published.size
      expect(rebuilt.map { |row| row[:id] }.uniq.size).to eq published.size
    end
  end
end
