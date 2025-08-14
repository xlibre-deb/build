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
require 'fileutils'
require_relative 'common'

class Matrix < Thor
  desc 'update', 'Update matrix.yaml'
  option :print, type: :boolean, desc: 'Print updated matrix without writing the file'
  def update
    matrix.each do |dist, body|
      releases = fetch_supported_releases(dist)
      body[:codenames] = releases.map { |row| row[:codename] }
      body[:suites] = fetch_suites(dist, releases)
    end
    yaml = matrix.to_yaml

    if options[:print]
      puts yaml
    else
      File.open("matrix.yaml", 'w') do |f|
        f.puts yaml
      end
    end
  end

  desc 'distconf', 'Update conf/distributions for the repos'
  option :dists, type: :array, desc: 'repos to update (default: all)'
  def distconf
    dists = options[:dists] || matrix.without_disabled.keys
    dists.each do |d|
      conf = gen_distconf(d.to_sym)
      FileUtils.mkdir_p("repos/#{d}/conf")
      File.open("repos/#{d}/conf/distributions", 'w') do |f|
        f.puts conf
      end
    end
  end

  no_commands do
    def fetch_supported_releases(dist)
      data_url = matrix[dist][:vars][:data_url]
      text = HTTP.get(data_url).to_s
      today = Date.today

      CSV.parse(text, headers: true, header_converters: :symbol).select do |row|
        codename = row[:codename].normalize_codename
        row[:codename] = codename
        next false if codename.excluded_codename?(dist)

        version = row[:version]
        next false if !version.nil? && !version.compatible_version?(dist)

        created = Date.parse(row[:created]) rescue nil
        eol = Date.parse(row[:eol]) rescue nil
        created && created <= today && (eol.nil? || today <= eol)
      end
    end

    def fetch_codename_for(dist, suite)
      release_url = matrix[dist][:vars][:release_url]
      url = sprintf(release_url, { release: suite })
      text = HTTP.get(url).to_s
      codename = text.match(/^Codename: *(.+?) *$/i)[1].normalize_codename
      return nil if codename.excluded_codename?(dist)
      codename
    end

    def fetch_suites(dist, releases)
      suites = matrix[dist][:suites]
      return nil if suites.nil?
      suites = suites.map do |k, v|
        [k, fetch_codename_for(dist, k)]
      end.to_h
      suites.merge!(suites) do |k, v|
        next nil if v.nil?
        release = releases.find { |r| r[:codename] == v }
        next nil if release.nil?
        version = release[:version]
        next nil if !version.nil? && !version.compatible_version?(dist)
        v
      end
      suites
    end

    def gen_distconf(dist)
      codenames = fetch_supported_releases(dist).map { |row| row[:codename] }
      arch = matrix[dist][:arch].join(' ')
      template = File.open('misc/distributions.tmpl', 'r', &:read)
      codenames.map do |codename|
        suite = matrix[dist][:suites]&.key(codename)
        suite = codename if suite.nil?
        values = { codename: codename, suite: suite, arch: arch }
        sprintf(template, values).strip
      end.join("\n\n")
    end
  end
end
