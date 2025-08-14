require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'parallel'
end

require 'parallel'
require_relative 'common'

class Packages < Thor
  desc 'clone [PACKAGES]', 'Clone packages into packages/ directory (default: clone all)'
  def clone(*packages)
    packages = config.packages[:packages].keys if packages.empty?
    prefix = config.packages[:prefix]
    FileUtils.mkdir_p('packages')
    Dir.chdir('packages') do
      Parallel.each(packages) do |pkg|
        version = config.packages[:packages][pkg.to_sym].gsub(':', '_')
        tag = "#{pkg}-#{version}"
        run! %(git clone --branch '#{tag}' '#{prefix}#{pkg}')
      end
    end
  end
end