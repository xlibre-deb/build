require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'parallel'
end

require 'parallel'
require_relative 'common'

class Packages < Thor
  desc 'clone [PACKAGES]', 'Clone packages into packages/ directory (default: clone all)'
  option :head, type: :boolean
  def clone(*packages)
    require_commands! %w[git]

    packages = config.packages[:packages].keys if packages.empty?
    prefix = config.packages[:prefix]
    head = options[:head].nil? ? config.packages[:head] : options[:head]

    FileUtils.mkdir_p('packages')
    Dir.chdir('packages') do
      Parallel.each(packages) do |pkg|
        version = config.packages[:packages][pkg].to_s.mangle
        tag = "xlibre/#{version}"
        run! %(git clone '#{prefix}#{pkg}')
        next if head
        Dir.chdir(pkg.to_s) do
          run! %(git checkout '#{tag}')
        end
      end
    end
  end
end

class Version < Thor
  namespace 'packages:version'

  desc 'get [PACKAGES]', 'Show package versions (default: all)'
  def get(*packages)
    require_commands! %w[dpkg-parsechangelog]
    each_pkg(packages) do |pkg|
      version = %x(dpkg-parsechangelog --show-field Version)
      puts "#{pkg}: #{version}"
    end
  end

  desc 'new [PACKAGES]', 'Add a new version to each package (default: all)'
  option :version, desc: 'new version (default: increase)'
  option :release, type: :boolean, desc: 'finalize package changelogs for release'
  option :commit, type: :boolean, desc: 'commit package version changes'
  def new(*packages)
    require_commands! %w[gbp]

    opts = []
    opts.push('--new-version', options[:version]) if options[:version]
    opts.push('--release') if options[:release]
    opts.push('--commit') if options[:commit]

    each_pkg(packages) do |pkg|
      tag_format = 'xlibre/%(version)s'
      puts "# Update the package version: #{pkg}"
      run! 'gbp', 'dch', '--git-author', *opts,
           '--debian-tag', tag_format, '--ignore-branch'
    end
  end

  no_commands do
    def each_pkg(packages, &block)
      Dir.glob('packages/*/').each do |dir|
        pkg = File.basename(dir)
        next if !packages.empty? && !packages.include?(pkg)
        Dir.chdir(dir) { block.call(pkg) }
      end
    end
  end
end
