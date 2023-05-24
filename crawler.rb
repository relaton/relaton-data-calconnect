# frozen_string_literal: true

require 'fileutils'
require 'relaton_calconnect'

FileUtils.rm_rf("data")

FileUtils.rm(Dir.glob("index*"))

RelatonCalconnect::DataFetcher.fetch

system "zip index-v1.zip index-v1.yaml"
system "git add index-v1.zip index-v1.yaml"
