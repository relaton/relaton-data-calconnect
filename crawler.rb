# frozen_string_literal: true

require 'fileutils'
require 'relaton/calconnect/data_fetcher'

FileUtils.rm_rf("data")

FileUtils.rm(Dir.glob("index*"))

Relaton::Calconnect::DataFetcher.fetch
