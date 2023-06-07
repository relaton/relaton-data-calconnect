# frozen_string_literal: true

require 'fileutils'
require 'relaton_calconnect'

FileUtils.rm_rf("data")

FileUtils.rm(Dir.glob("index*"))

RelatonCalconnect::DataFetcher.fetch
