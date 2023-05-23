require 'fileutils'

FileUtils.rm_rf("data")

require 'relaton_calconnect'
RelatonCalconnect::DataFetcher.fetch
