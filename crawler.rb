require 'fileutils'

t1 = Time.now
puts "Started at: #{t1}"

FileUtils.rm_rf("data")
system("relaton fetch-data calconnect-org")

t2 = Time.now
puts "Stopped at: #{t2}"
puts "Done in: #{(t2 - t1).round} sec."
