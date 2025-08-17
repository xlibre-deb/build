require 'stringio'
require 'fileutils'
require_relative 'common'

class Build < Thor
  include Thor::Actions

  desc 'use-remote-builder NAME URL', 'Use remote builder instance'
  def use_remote_builder(name, url)
    require_commands! %w[docker]

    run! %(docker buildx rm '#{name}' >/dev/null 2>&1 ||:)
    run! %(docker buildx create --name '#{name}' --driver=remote '#{url}')
    run! %(docker buildx use '#{name}')
  end

  desc 'list-targets', 'List build targets'
  def list_targets
    puts config.matrix.without_disabled.target_names.join("\n")
  end

  desc 'target TARGET', 'Build packages for a specific target'
  option :packages, type: :array, desc: 'packages to build (default: all)'
  option :no_check, type: :boolean, desc: 'skip build result check'
  def target(target)
    require_commands! %w[docker]

    dist, codename, arch = target.split('-').map(&:to_sym)
    image = config.matrix[dist][:vars][:image]
    image = "#{image}:#{codename}"
    systemd = config.matrix[dist][:vars][:systemd]
    packages = options[:packages]&.join(' ') || '*'
    run! %(
      docker buildx build \
        --no-cache-filter build,export \
        --tag xlibre-build-#{target} \
        --platform linux/#{arch} \
        --build-arg BASEIMAGE=#{image} \
        --build-arg TARGET_NAME=#{target} \
        --build-arg PACKAGES='#{packages}' \
        --build-arg SYSTEMD='#{systemd}' \
        -o type=local,dest=output/ \
        -f misc/docker/Dockerfile \
        ./
    )

    return if options[:no_check]
    if !File.exist?("output/#{target}/build-status") ||
        File.read("output/#{target}/build-status").strip != 'success'
      abort "Build failed! See output at: output/#{target}/"
    end
  end

  desc 'local', 'Build packages on the host system without using Docker. Requires root privileges'
  option :systemd, type: :boolean, desc: 'enable or disable systemd support'
  option :packages, type: :array, desc: 'packages to build (default: all)'
  def local
    require_commands! %w[uscan debuild apt-get dpkg-architecture]

    systemd = options[:systemd]
    packages = options[:packages]&.join(' ') || '*'

    if systemd.nil?
      $stderr.puts 'Specify --systemd or --no-systemd'
      exit 1
    end

    abstmp = File.absolute_path('tmp')
    if File.exist?(abstmp)
      unless File.directory?(abstmp)
        $stderr.puts "'#{abstmp}' exists but is not a directory."
        exit 1
      end
      if yes?("Directory '#{abstmp}' already exists. Delete it to proceed? (y/n)")
        FileUtils.rm_rf(abstmp, secure: true)
        if File.exist?(abstmp)
          $stderr.puts "Directory '#{abstmp}' could not be deleted. Possible permission issue."
          exit 1
        end
      else
        $stderr.puts 'Stopped.'
        exit 1
      end
    end

    Dir.mkdir(abstmp)
    run! %(cd packages && cp -r #{packages} ../tmp/)

    install_pgks = %w[devscripts]
    install_pgks.concat(%w[libdbus-1-dev libsystemd-dev systemd-dev]) if systemd
    run! 'apt-get', 'update'
    run! 'env', 'DEBIAN_FRONTEND=noninteractive',
         'apt-get', 'install', '-y', '--no-install-recommends', *install_pgks

    run! 'env', "SYSTEMD=#{systemd}", 'bash', 'misc/docker/build.sh', abstmp
  end

  desc 'bake', 'Build using docker bake file'
  option :no_check, type: :boolean, desc: 'skip build result check'
  def bake
    require_commands! %w[docker]
    run! %(docker buildx bake)

    return if options[:no_check]
    Dir.glob('output/*/') do |dir|
      if !File.exist?("#{dir}/build-status") ||
          File.read("#{dir}/build-status").strip != 'success'
        abort 'Build failed! See output at: output/*/'
      end
    end
  end
end

class Bake < Thor
  namespace 'build:bake'

  desc 'gen', 'Generate docker bake file'
  option :targets, type: :array, desc: 'targets to build (default: all)'
  option :packages, type: :array, desc: 'packages to build (default: all)'
  option :arch, type: :array, desc: 'architectures to build (default: all)'
  def gen
    targets = options[:targets] || config.matrix.without_disabled.target_names
    packages = options[:packages]&.join(' ') || '*'

    targets.select! do |target|
      *_, arch = target.split('-')
      options[:arch].nil? || options[:arch].include?(arch)
    end

    buf = StringIO.new
    buf.puts <<~EOF
      group "default" {
        targets = [
      #{targets.map { |t| "    \"#{t}\"" }.join(",\n")}
        ]
      }
    EOF

    targets.each do |target|
      dist, codename, arch = target.split('-').map(&:to_sym)
      image = config.matrix[dist][:vars][:image]
      image = "#{image}:#{codename}"
      systemd = config.matrix[dist][:vars][:systemd]

      buf.puts
      buf.puts <<~EOF
        target "#{target}" {
          context = "."
          dockerfile = "misc/docker/Dockerfile"
          no-cache-filter = ["build", "export"]
          args = {
            TARGET_NAME = "#{target}"
            BASEIMAGE = "#{image}"
            PACKAGES = "#{packages}"
            SYSTEMD = "#{systemd}"
          }
          output = [{ type = "local", dest = "output/" }]
          tags = ["xlibre-build-#{target}"]
          platforms = ["#{arch}"]
        }
      EOF
    end

    File.open('docker-bake.hcl', 'w') do |f|
      f.puts buf.string
    end
  end
end
