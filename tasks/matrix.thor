require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'http'
  gem 'csv'
end

require 'http'
require 'csv'
require 'date'
require 'yaml'
require 'json'
require 'fileutils'
require_relative 'common'

class Matrix < Thor
  desc 'update', 'Update matrix.yaml'
  option :print, type: :boolean, desc: 'Print updated matrix without writing the file'
  def update
    config.matrix.each do |dist, body|
      releases = fetch_supported_releases(dist)
      body[:codenames] = releases.map { |row| row[:codename] }
      body[:suites] = fetch_suites(dist, releases)
    end
    yaml = config.matrix.to_yaml

    if options[:print]
      puts yaml
    else
      File.open('matrix.yaml', 'w') do |f|
        f.puts yaml
      end
    end
  end

  desc 'jobs', 'Output build jobs as JSON'
  option :runners, type: :hash, required: true, desc: 'runner image for each target'
  option :compact, type: :boolean
  def jobs
    targets = config.matrix.without_disabled.targets
    runners = options[:runners]
    targets = targets.filter_map do |target|
      runner = runners[target[:arch]]
      next if runner.nil?
      target[:runner] = runner
      target
    end
    if options[:compact]
      puts targets.to_json
    else
      puts JSON.pretty_generate(targets)
    end
  end

  no_commands do
    def fetch_supported_releases(dist)
      data_url = config.matrix[dist][:vars][:data_url]
      released_only = config.matrix[dist][:vars][:released_only]
      text = HTTP.get(data_url).to_s
      today = Date.today

      CSV.parse(text, headers: true, header_converters: :symbol).select do |row|
        codename = row[:codename].normalize_codename
        row[:codename] = codename
        next false if codename.excluded_codename?(dist)

        version = row[:version]
        next false if !version.nil? && !version.compatible_version?(dist)

        if released_only
          release = Date.parse(row[:release]) rescue nil
          next false if release.nil? || today < release
        end

        created = Date.parse(row[:created]) rescue nil
        eol = Date.parse(row[:eol]) rescue nil
        created && created <= today && (eol.nil? || today <= eol)
      end
    end

    def fetch_codename_for(dist, suite)
      release_url = config.matrix[dist][:vars][:release_url]
      url = format(release_url, { release: suite })
      text = HTTP.get(url).to_s
      codename = text.match(/^Codename: *(.+?) *$/i)[1].normalize_codename
      return nil if codename.excluded_codename?(dist)
      codename
    end

    def fetch_suites(dist, releases)
      suites = config.matrix[dist][:suites]
      return nil if suites.nil?
      suites = suites.to_h do |k, _v|
        [k, fetch_codename_for(dist, k)]
      end
      suites.merge!(suites) do |_k, v|
        next nil if v.nil?
        release = releases.find { |r| r[:codename] == v }
        next nil if release.nil?
        version = release[:version]
        next nil if !version.nil? && !version.compatible_version?(dist)
        v
      end
      suites
    end
  end
end
