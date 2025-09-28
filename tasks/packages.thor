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
        run! %(git clone '#{prefix}#{pkg}')
        next if head
        Dir.chdir(pkg.to_s) do
          version = config.packages[:packages][pkg].to_s.mangle
          tag = "xlibre/#{version}"
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
  option :urgency, desc: 'urgency level'
  option :release, type: :boolean, desc: 'finalize package changelogs for release'
  option :commit, type: :boolean, desc: 'commit package version changes'
  option :tag, type: :boolean, desc: 'tag package releases'
  def new(*packages)
    require_commands! %w[gbp]
    set_envs!

    opts = []
    opts.push('--new-version', options[:version]) if options[:version]
    opts.push('--urgency', options[:urgency]) if options[:urgency]
    opts.push('--release') if options[:release]
    opts.push('--commit') if options[:commit]

    each_pkg(packages) do |pkg|
      puts "# Update the package version: #{pkg}"
      run! 'gbp', 'dch', *opts,
           '--debian-branch', 'xlibre/latest',
           '--debian-tag', 'xlibre/%(version)s',
           '--upstream-branch', 'upstream/latest',
           '--upstream-tag', 'upstream/%(version)s'
      next unless options[:tag]

      tag_msg_format = 'Tag %(pkg)s %(version)s'
      user_kp = user_signingkey
      run! 'gbp', 'tag',
           '--sign-tags',
           '--keyid', user_kp,
           '--debian-branch', 'xlibre/latest',
           '--debian-tag', 'xlibre/%(version)s',
           '--debian-tag-msg', tag_msg_format
    end
  end

  desc 'tag [PACKAGES]', 'Tag package releases (default: all packages)'
  def tag(*packages)
    require_commands! %w[git gbp]

    tag_msg_format = 'Tag %(pkg)s %(version)s'
    user_kp = user_signingkey

    each_pkg(packages) do |pkg|
      puts "# Tag package version: #{pkg}"
      run! 'gbp', 'tag',
           '--sign-tags',
           '--keyid', user_kp,
           '--debian-branch', 'xlibre/latest',
           '--debian-tag', 'xlibre/%(version)s',
           '--debian-tag-msg', tag_msg_format
    end
  end

  desc 'push [PACKAGES]', 'Push packages to remote Git repos (default: all packages)'
  option :dry_run, type: :boolean
  def push(*packages)
    require_commands! %w[gbp]

    opts = []
    opts.push('--dry-run') if options[:dry_run]

    each_pkg(packages) do |pkg|
      puts "# Push #{pkg} to remote repo"
      format_file = 'debian/source/format'
      is_native = File.file?(format_file) && File.read(format_file).include?('native')
      run! %(git checkout upstream/latest >/dev/null) unless is_native
      run! %(git checkout xlibre/latest >/dev/null)
      run! 'gbp', 'push', *opts,
           '--debian-branch', 'xlibre/latest',
           '--debian-tag', 'xlibre/%(version)s',
           '--upstream-branch', 'upstream/latest',
           '--upstream-tag', 'upstream/%(version)s',
           '--pristine-tar'
    end
  end

  desc 'import-upstream [PACKAGES]', 'Import upstream source (default: all packages)'
  def import_upstream(*packages)
    require_commands! %w[gbp git]
    user_kp = user_signingkey

    each_pkg(packages) do |pkg|
      format_file = 'debian/source/format'
      is_native = File.file?(format_file) && File.read(format_file).include?('native')
      if is_native
        puts "# Skip (native): #{pkg}"
        next
      end
      run! %(git checkout upstream/latest >/dev/null)
      run! %(git checkout xlibre/latest >/dev/null)
      puts "# Import upstream source: #{pkg}"
      run! 'gbp', 'import-orig',
           '--uscan',
           '--pristine-tar',
           '--sign-tags',
           '--keyid', user_kp,
           '--debian-branch', 'xlibre/latest',
           '--upstream-branch', 'upstream/latest',
           '--upstream-tag', 'upstream/%(version)s'
    end
  end

  no_commands do
    def set_envs!
      name = %x(git config --local user.name)
      name = %x(git config --global user.name) if $?.exitstatus != 0
      raise 'Git user name not configured.' if $?.exitstatus != 0
      email = %x(git config --local user.email)
      email = %x(git config --global user.email) if $?.exitstatus != 0
      raise 'Git user email not configured.' if $?.exitstatus != 0
      ENV['DEBFULLNAME'] = name.strip
      ENV['DEBEMAIL'] = email.strip
    end

    def each_pkg(packages, &block)
      Dir.glob('packages/*/').each do |dir|
        pkg = File.basename(dir)
        next if !packages.empty? && !packages.include?(pkg)
        Dir.chdir(dir) { block.call(pkg) }
      end
    end
  end
end
