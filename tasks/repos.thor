require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'parallel'
end

require 'parallel'
require 'fileutils'
require_relative 'common'

class Repos < Thor
  desc 'clone [REPOS]', 'Clone repos into repos/ directory (default: clone all)'
  def clone(*repos)
    repos = config.matrix.without_disabled.keys if repos.empty?
    FileUtils.mkdir_p('repos')
    Dir.chdir('repos') do
      Parallel.each(repos) do |name|
        repo_url = config.matrix[name.to_sym][:vars][:repo]
        run! %(git clone #{repo_url})
      end
    end
  end

  desc 'include', 'Include built packages in repos'
  def include
    deb_files = Dir.glob('output/*/*.deb')
    deb_files.each do |path|
      puts "# Include: #{path}"

      target = File.basename(File.dirname(path))
      distro, codename, arch = target.split('-')

      FileUtils.mkdir_p("repos/#{distro}/dists/#{codename}/pool/main/#{arch}")
      FileUtils.cp(path, "repos/#{distro}/dists/#{codename}/pool/main/#{arch}/")
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
      distro, codename, *_ = target.split('-')

      FileUtils.mkdir_p("repos/#{distro}/dists/#{codename}/pool/main/source")
      FileUtils.cp(path, "repos/#{distro}/dists/#{codename}/pool/main/source/")
    end
  end

  desc 'update [REPOS]', 'Update repo metadata (default: update all repos)'
  def update(*repos)
    repos = config.matrix.without_disabled.keys if repos.empty?
    kp = key_fingerprint

    repos.each do |name|
      data = config.matrix[name.to_sym]
      codenames = data[:codenames]
      arch_list = data[:arch]

      FileUtils.mkdir_p("repos/#{name}/")
      FileUtils.cp('misc/key.asc', "repos/#{name}/")

      FileUtils.mkdir_p("repos/#{name}/dists")
      Dir.chdir("repos/#{name}/dists") do
        data[:suites]&.each do |suite, release|
          FileUtils.remove_file(suite.to_s) if File.symlink?(suite.to_s)
          File.symlink(release.to_s, suite.to_s) unless release.nil?
        end
      end

      Dir.chdir("repos/#{name}") do
        codenames.each do |release|
          Apt.sources(release)
          Apt.sources_xz(release)

          arch_list.each do |arch|
            Apt.packages(release, arch)
            Apt.packages_xz(release, arch)
            Apt.contents(release, arch)
            Apt.contents_xz(release, arch)
          end

          suite = data[:suites]&.key(release)
          allarch = (['source'] + arch_list).join(' ')
          Apt.release(release, suite, allarch)
          Apt.release_gpg(release, kp)
          Apt.inrelease(release, kp)
        end
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
    suite = codename if suite.nil?
    template = File.read('../../misc/Release.tmpl')
    values = { codename: release, suite: suite, arch: allarch }
    text = sprintf(template, values).strip + "\n"
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