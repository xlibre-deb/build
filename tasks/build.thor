require 'stringio'
require_relative 'common'

class Build < Thor
  desc 'use-remote-builder NAME URL', 'Use remote builder instance'
  def use_remote_builder(name, url)
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
  def target(target)
    dist, codename, arch = target.split('-').map(&:to_sym)
    image = matrix[dist][:vars][:image]
    image = "#{image}:#{codename}"
    systemd = matrix[dist][:vars][:systemd]
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
  end

  desc 'bake', 'Build using docker bake file'
  def bake
    run! %(docker buildx bake --no-cache)
  end
end

class Bake < Thor
  namespace 'build:bake'

  desc 'gen', 'Generate docker bake file'
  option :targets, type: :array, desc: 'targets to build (default: all)'
  option :packages, type: :array, desc: 'packages to build (default: all)'
  def gen
    targets = options[:targets] || config.matrix.without_disabled.target_names
    packages = options[:packages]&.join(' ') || '*'

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
      image = matrix[dist][:vars][:image]
      image = "#{image}:#{codename}"
      systemd = matrix[dist][:vars][:systemd]

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