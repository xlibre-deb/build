require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'parallel'
end

require 'parallel'

class Packages < Thor
  desc 'clone', 'Clone packages into packages/ directory'
  def clone
    packages = File.open('packages.list', 'r', &:read).strip.lines.map(&:strip)
    Dir.chdir("packages") do
      Parallel.each(packages) do |repo|
        run! %(git clone #{repo})
      end
    end
  end
end