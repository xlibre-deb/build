require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'http'
  gem 'terminal-table'
  gem 'parallel'
end

require 'http'
require 'json'
require 'fileutils'
require 'digest'
require 'terminal-table'
require 'parallel'
require_relative 'common'

GITHUB_API_URL = 'https://api.github.com/repos/xlibre-deb/build'.freeze
GITHUB_API_VERSION = '2022-11-28'.freeze
BUILD_WORKFLOW = 'build-packages'.freeze

class CI < Thor
end

class Runs < Thor
  namespace 'ci:runs'

  class_option :token, desc: 'GitHub token (default: from $GITHUB_TOKEN)'

  desc 'list', 'List workflow runs'
  option :n, type: :numeric, default: 8, desc: 'Print last N runs only'
  option :success, type: :boolean, desc: 'Print successful runs only'
  option :name, desc: 'Filter by workflow name'
  def list
    token = options[:token] || ENV['GITHUB_TOKEN']
    token = nil if token.strip.empty?
    headers = {
      accept: 'application/vnd.github+json',
      x_github_api_version: GITHUB_API_VERSION,
    }
    headers[:authorization] = "Bearer #{token}" if token

    text = HTTP[**headers].get("#{GITHUB_API_URL}/actions/runs").to_s
    result = JSON.parse(text, symbolize_names: true)
    runs = result[:workflow_runs]
    runs.filter! { |run| run[:conclusion] == 'success' } if options[:success]
    runs.filter! { |run| run[:name] == options[:name] } if options[:name]
    rows = runs.first(options[:n]).map do |run|
      [
        run[:id],
        run[:name].ellipsize(15, keep_tail: true),
        run[:head_branch].ellipsize(15, keep_tail: true),
        run[:display_title].ellipsize(30),
        run[:conclusion],
        run[:created_at],
      ]
    end
    table = ::Terminal::Table.new \
      rows: rows,
      headings: %w[id name branch title result at]
    puts table
  end

  desc 'last [WORKFLOW_NAME]', 'Get last successful run (default: last successful build workflow)'
  def last(name = BUILD_WORKFLOW)
    invoke :list, [], n: 1, success: true, name: name
  end
end

class Artifacts < Thor
  namespace 'ci:artifacts'

  class_option :token, desc: 'GitHub token (default: from $GITHUB_TOKEN)'

  desc 'dl [RUN_ID]', 'Download build artifacts (default: from last successful run)'
  def dl(run_id = nil)
    require_commands! %w[aria2c]

    token = options[:token] || ENV['GITHUB_TOKEN']
    token = nil if token.strip.empty?
    abort 'Token required' unless token
    headers = {
      accept: 'application/vnd.github+json',
      x_github_api_version: GITHUB_API_VERSION,
    }
    headers[:authorization] = "Bearer #{token}" if token

    text = HTTP[**headers].get("#{GITHUB_API_URL}/actions/runs").to_s
    result = JSON.parse(text, symbolize_names: true)
    if run_id.nil?
      run = result[:workflow_runs].find { |run| run[:conclusion] == 'success' }
      run_id = run[:id]
    else
      run = result[:workflow_runs].find { |run| run[:id] == run_id }
    end
    abort 'No successful run found' if run.nil?

    puts "# Download from the run - id: #{run_id} / title: #{run[:display_title]}"

    text = HTTP[**headers].get("#{GITHUB_API_URL}/actions/runs/#{run_id}/artifacts").to_s
    result = JSON.parse(text, symbolize_names: true)
    FileUtils.mkdir_p('downloads')
    puts '# Fetching file list to download'
    artifacts = Parallel.map(result[:artifacts]) do |artf|
      {
        name: artf[:name],
        digest: artf[:digest],
        url: final_url(token, artf[:archive_download_url]),
      }
    end
    artifacts.each { |artf| puts " - #{artf[:name]}" }
    puts '# Download files'
    Parallel.each(artifacts) do |artf|
      download(artf[:url])
      check_hash(artf[:name], artf[:digest])
    end
  end

  no_commands do
    def final_url(token, url)
      headers = {
        accept: 'application/vnd.github+json',
        x_github_api_version: GITHUB_API_VERSION,
        authorization: "Bearer #{token}",
      }
      HTTP[**headers].follow.get(url).uri.to_s
    end

    def download(url)
      run! 'aria2c', '-s', '16', '-x', '16', '--dir', 'downloads', url
    end

    def check_hash(name, digest)
      filehash = Digest::SHA256.file("downloads/#{name}.zip").hexdigest
      if digest.strip.downcase != "sha256:#{filehash}"
        abort "File does not match the hash!: downloads/#{name}.zip"
      end
      puts "## File hash matched: downloads/#{name}.zip"
    end
  end
end
