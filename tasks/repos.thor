require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'parallel'
  gem 'terminal-table'
end

require 'parallel'
require 'terminal-table'
require 'fileutils'
require_relative 'common'

class Repos < Thor
  desc 'clone [REPOS]', 'Clone repos into repos/ directory (default: clone all)'
  option :test, type: :boolean, default: true, desc: 'clone *-test repos instead'
  def clone(*repos)
    require_commands! %w[git]

    repos = config.matrix.without_disabled.keys if repos.empty?
    FileUtils.mkdir_p('repos')
    Dir.chdir('repos') do
      Parallel.each(repos) do |name|
        repo_url = config.matrix[name.to_sym][:vars][:repo]
        repo_url = "#{repo_url}-test" if options[:test]
        run! %(git clone #{repo_url} #{name})
      end
    end
  end

  desc 'include', 'Include built packages in repos'
  def include
    deb_files = Dir.glob('output/*/*.deb')
    deb_files.each do |path|
      puts "# Include: #{path}"

      target = File.basename(File.dirname(path))
      distro, codename, _arch = target.split('-')
      deb_arch = File.basename(path)[/_([A-Za-z0-9\-]+).deb$/, 1]

      FileUtils.mkdir_p("repos/#{distro}/dists/#{codename}/pool/main/#{deb_arch}")
      FileUtils.cp(path, "repos/#{distro}/dists/#{codename}/pool/main/#{deb_arch}/")
    end

    source_files = Dir.glob('output/*/*.{debian.tar.*,dsc,orig.tar.*}')
    source_files.each do |path|
      if File.extname(path) == '.dsc'
        is_native = File.read(path) =~ /^Format:.*native/i
        if is_native
          puts "# Skip (native): #{path}"
          next
        end
      end

      puts "# Include: #{path}"
      target = File.basename(File.dirname(path))
      distro, codename, = target.split('-')

      FileUtils.mkdir_p("repos/#{distro}/dists/#{codename}/pool/main/source")
      FileUtils.cp(path, "repos/#{distro}/dists/#{codename}/pool/main/source/")
    end
  end

  desc 'update [REPOS]', 'Update repo metadata (default: update all repos)'
  option :resign, type: :boolean, desc: 're-sign *.dsc files that are already signed'
  def update(*repos)
    require_commands! %w[debsign apt-ftparchive gpg xz]

    repos = config.matrix.without_disabled.keys if repos.empty?
    kp = key_fingerprint

    repos.each do |name|
      data = config.matrix[name.to_sym]
      codenames = data[:codenames].dup
      suites = data[:suites].dup
      arch_list = data[:arch]
      alias_codenames = []

      dsc_files = Dir.glob("repos/#{name}/**/*.dsc")
      dsc_files.each do |path|
        puts "# Sign: #{path}"
        if options[:resign]
          run! %(debsign --re-sign -k #{kp} #{path} >/dev/null)
        else
          run! %(debsign --no-re-sign -k #{kp} #{path} >/dev/null)
        end
      end

      FileUtils.mkdir_p("repos/#{name}/dists")
      Dir.chdir("repos/#{name}/dists") do
        data[:suites]&.each do |suite, release|
          FileUtils.remove_file(suite.to_s) if File.symlink?(suite.to_s)
          File.symlink(release.to_s, suite.to_s) unless release.nil?
        end
        data[:vars][:aliases]&.each do |a|
          old = a[:old]
          new_codename = a[:new][:codename]
          new_suite = a[:new][:suite]
          FileUtils.remove_file(new_suite) if !new_suite.nil? && File.symlink?(new_suite)
          next if new_codename == new_suite
          File.symlink(new_codename, new_suite) unless new_suite.nil?

          FileUtils.mkdir_p(new_codename)
          FileUtils.remove_file("#{new_codename}/main", force: true)
          File.symlink("../#{old}/main", "#{new_codename}/main")
          FileUtils.remove_file("#{new_codename}/pool", force: true)
          File.symlink("../#{old}/pool", "#{new_codename}/pool")

          codenames.append(new_codename)
          alias_codenames.append(new_codename)
          suites[new_suite.to_sym] = new_codename unless new_suite.nil?
        end
      end

      Dir.chdir("repos/#{name}") do
        codenames.each do |release|
          is_alias = alias_codenames.include?(release)

          unless is_alias
            Apt.sources(release)
            Apt.sources_xz(release)

            Apt.packages(release, 'all')
            Apt.packages_xz(release, 'all')
            Apt.contents(release, 'all')
            Apt.contents_xz(release, 'all')

            arch_list.each do |arch|
              Apt.packages(release, arch)
              Apt.packages_xz(release, arch)
              Apt.contents(release, arch)
              Apt.contents_xz(release, arch)
            end
          end

          suite = suites&.key(release)
          allarch = (['source'] + arch_list).join(' ')
          Apt.release(release, suite, allarch)
          Apt.release_gpg(release, kp)
          Apt.inrelease(release, kp)
        end
      end
    end
  end

  desc 'update-readme [REPOS]', 'Update repository READMEs (default: all)'
  def update_readme(*repos)
    repos = config.matrix.without_disabled.keys if repos.empty?
    ptn = /^(#+ *Support Status).*\z/im
    repos.each do |repo|
      releases = config.matrix.all_releases(repo.to_sym)

      Dir.chdir("repos/#{repo}") do
        readme = File.read('README.md')
        if ptn.match?(readme)
          readme = readme.sub(ptn, "\\1\n\n")
        else
          readme += "\n\n## Support Status\n\n"
        end

        table = ::Terminal::Table.new do |t|
          releases.each do |r|
            relname = r[:codename]
            relname = "#{relname} (#{r[:suite]})" if r[:suite]
            arch = r[:alias_of] ? '' : config.matrix[repo.to_sym][:arch].join(', ')
            status = r[:alias_of] ? "Alias of #{r[:alias_of]}" : '✅'
            t << [relname, status, arch]
          end
        end
        table.headings = %w[Release Status Arch]
        table.style = { border: :markdown }

        readme += "#{table}\n"
        File.write('README.md', readme)
      end
    end
  end
end

module Apt
  def self.sources(release)
    FileUtils.mkdir_p("dists/#{release}/pool/main")
    FileUtils.mkdir_p("dists/#{release}/main/source")
    run! %(
      apt-ftparchive sources dists/#{release}/pool/main/ \
        > dists/#{release}/main/source/Sources
    )
  end

  def self.sources_xz(release)
    run! %(
      cat dists/#{release}/main/source/Sources \
        | xz -9 > dists/#{release}/main/source/Sources.xz
    )
  end

  def self.packages(release, arch)
    FileUtils.mkdir_p("dists/#{release}/pool/main")
    FileUtils.mkdir_p("dists/#{release}/main/binary-#{arch}")
    run! %(
      apt-ftparchive packages dists/#{release}/pool/main/ \
        > dists/#{release}/main/binary-#{arch}/Packages
    )
  end

  def self.packages_xz(release, arch)
    run! %(
      cat dists/#{release}/main/binary-#{arch}/Packages \
        | xz -9 > dists/#{release}/main/binary-#{arch}/Packages.xz
    )
  end

  def self.contents(release, arch)
    run! %(
      apt-ftparchive contents -a #{arch} dists/#{release}/ \
        > dists/#{release}/main/Contents-#{arch}
    )
  end

  def self.contents_xz(release, arch)
    run! %(
      cat dists/#{release}/main/Contents-#{arch} \
        | xz -9 > dists/#{release}/main/Contents-#{arch}.xz
    )
  end

  def self.release(release, suite, allarch)
    suite = release if suite.nil?
    template = File.read('../../misc/Release.tmpl')
    values = { codename: release, suite: suite, arch: allarch }
    text = format(template, values).strip + "\n"
    File.write("dists/#{release}/Release", text)
    run! %(
      apt-ftparchive release dists/#{release}/ \
        >> dists/#{release}/Release
    )
  end

  def self.release_gpg(release, key_fingerprint)
    run! %(
      cat dists/#{release}/Release \
        | gpg --local-user #{key_fingerprint} -qabs \
        > dists/#{release}/Release.gpg
    )
  end

  def self.inrelease(release, key_fingerprint)
    run! %(
      cat dists/#{release}/Release \
        | gpg --local-user #{key_fingerprint} -qabs --clearsign \
        > dists/#{release}/InRelease
    )
  end
end
