require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'parallel'
end

require 'parallel'
require_relative 'common'

class Pkg < Thor
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

  desc 'get-version [PACKAGES]', 'Show package versions (default: package in current directory)'
  option :all, type: :boolean, desc: 'Run on all packages'
  def get_version(*packages)
    require_commands! %w[dpkg-parsechangelog]
    packages = [ File.basename($current_dir) ] if packages.empty?
    packages = [] if options[:all]
    each_pkg(packages) do |pkg|
      version = %x(dpkg-parsechangelog --show-field Version)
      puts "#{pkg}: #{version}"
    end
  end

  desc 'new-version [PACKAGES]', 'Add a new version to each package (default: package in current directory)'
  option :all, type: :boolean, desc: 'Run on all packages'
  option :version, desc: 'new version (default: increase)'
  option :urgency, desc: 'urgency level'
  option :release, type: :boolean, desc: 'finalize package changelogs for release'
  option :commit, type: :boolean, desc: 'commit package version changes'
  option :tag, type: :boolean, desc: 'tag package releases'
  def new_version(*packages)
    require_commands! %w[gbp git]
    set_envs!

    packages = [ File.basename($current_dir) ] if packages.empty?
    packages = [] if options[:all]

    opts = []
    opts.push('--new-version', options[:version]) if options[:version]
    opts.push('--urgency', options[:urgency]) if options[:urgency]
    opts.push('--release') if options[:release]
    opts.push('--commit') if options[:commit]

    each_pkg(packages) do |pkg|
      head_tags = %x(git tag --points-at HEAD)
      if head_tags.include?('xlibre/')
        puts "Skip (already tagged): #{pkg}"
        next
      end

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

  desc 'tag-version [PACKAGES]', 'Tag package releases (default: package in current directory)'
  option :all, type: :boolean, desc: 'Run on all packages'
  def tag_version(*packages)
    require_commands! %w[git gbp]

    packages = [ File.basename($current_dir) ] if packages.empty?
    packages = [] if options[:all]

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

  desc 'push [PACKAGES]', 'Push packages to remote Git repos (default: package in current directory)'
  option :all, type: :boolean, desc: 'Run on all packages'
  option :dry_run, type: :boolean
  def push(*packages)
    require_commands! %w[gbp]

    packages = [ File.basename($current_dir) ] if packages.empty?
    packages = [] if options[:all]

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

  desc 'import-upstream [PACKAGES]', 'Import upstream source (default: package in current directory)'
  option :all, type: :boolean, desc: 'Run on all packages'
  def import_upstream(*packages)
    require_commands! %w[gbp git uscan]
    user_kp = user_signingkey

    packages = [ File.basename($current_dir) ] if packages.empty?
    packages = [] if options[:all]

    each_pkg(packages) do |pkg|
      format_file = 'debian/source/format'
      is_native = File.file?(format_file) && File.read(format_file).include?('native')
      if is_native
        puts "# Skip (native): #{pkg}"
        next
      end
      version_status = %x(uscan --report-status --no-download)
      if version_status.include?('Package is up to date')
        puts "# Skip (up-to-date): #{pkg}"
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

  desc 'commit [GIT_OPTIONS]', 'Commit the changes with updated changelog'
  def commit(*git_options)
    require_commands! %w[gbp git]
    Dir.chdir($current_dir) do
      run! 'git', 'commit', *git_options
      run! 'gbp', 'dch'
      run! 'git', 'add', 'debian/changelog'
      run! 'git', 'commit', '--amend', '--no-edit'
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
