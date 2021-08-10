# frozen_string_literal:true

require 'relaton_calconnect'

#
# Relaton-calconnect data fetcher
#
class DataFetcher
  DOMAIN = 'https://standards.calconnect.org/'
  SCHEME, HOST = DOMAIN.split(%r{:?/?/})
  ENDPOINT = 'https://standards.calconnect.org/relaton/index.yaml'
  DATADIR = 'data'
  DATAFILE = File.join DATADIR, 'bibliography.yml'
  ETAGFILE = File.join DATADIR, 'etag.txt'

  def self.fetch_data
    new.fetch_data
  end

  #
  # fetch data form server and save it to file.
  #
  def fetch_data
    resp = Faraday.new(ENDPOINT, headers: { 'If-None-Match' => etag }).get
    # return if there aren't any changes since last fetching
    return unless resp.status == 200

    self.etag = resp[:etag]
    data = YAML.safe_load resp.body
    data['root']['items'].each { |doc| parse_page doc }
  end

  private

  #
  # Parse document and write it to file
  #
  # @param [Hash] doc
  #
  def parse_page(doc)
    bib = bib_item doc
    bib.link.each { |l| l.content.merge!(scheme: SCHEME, host: HOST) unless l.content.host }
    xml = bib.to_xml bibdata: true
    file = File.join DATADIR, "#{doc['docid']['id'].downcase.gsub(%r{[/\s:]}, '_')}.xml"
    if File.exist? file
      warn "#{file} exist"
    else
      File.write file, xml, encoding: 'UTF-8'
    end
  end

  def bib_item(doc)
    links = array(doc['link'])
    link = links.detect { |l| l['type'] == 'rxl' }
    if link
      bib = fetch_bib_xml link['content']
      update_links bib, links
    else
      RelatonCalconnect::CcBibliographicItem.from_hash doc_to_hash(doc)
    end
  end

  def update_links(bib, links)
    links.each do |l|
      tu = l.transform_keys(&:to_sym)
      bib.link << RelatonBib::TypedUri.new(**tu) unless bib.url(l['type'])
    end
    bib
  end

  #
  # Fix editorial group
  #
  # @param [Hash] doc
  #
  # @return [Hash]
  #
  def doc_to_hash(doc)
    array(doc['editorialgroup']).each do |eg|
      tc = eg.delete('technical_committee')
      eg.merge!(tc) if tc
    end
    doc
  end

  #
  # Wrap into Array if not Array
  #
  # @param [Array, Hash, String, nil] content
  #
  # @return [Array<Hash, String>]
  #
  def array(content)
    case content
    when Array then content
    when nil then []
    else [content]
    end
  end

  # @param url [String]
  # @return [String] XML
  def fetch_bib_xml(url)
    rxl = get_rxl url
    uri_rxl = rxl.at("uri[@type='rxl']")
    if uri_rxl
      uri_xml = rxl.xpath('//uri').to_xml
      rxl = get_rxl uri_rxl.text
      docid = rxl.at '//docidentifier'
      docid.add_previous_sibling uri_xml
    end
    xml = rxl.to_xml.gsub!(%r{(</?)technical-committee(>)}, '\1committee\2')
    RelatonCalconnect::XMLParser.from_xml xml
  end

  # @param path [String]
  # @return [Nokogiri::XML::Document]
  def get_rxl(path)
    resp = Faraday.get DOMAIN + path
    Nokogiri::XML resp.body
  end

  #
  # Read ETag from file
  #
  # @return [String, NilClass]
  def etag
    @etag ||= File.exist?(ETAGFILE) ? File.read(ETAGFILE, encoding: 'UTF-8') : nil
  end

  #
  # Save ETag to file
  #
  # @param tag [String]
  def etag=(e_tag)
    File.write ETAGFILE, e_tag, encoding: 'UTF-8'
  end
end

DataFetcher.fetch_data
