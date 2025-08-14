require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'parallel'
end

require 'parallel'

class Repos < Thor
  desc 'clone', 'Clone repos into repos/ directory'
  def clone
    Parallel.each(matrix) do |dist, body|
      repo = body[:vars][:repo]
      run! %(git clone #{repo})
    end
  end

  desc 'include', 'Include built packages in repos'
  def include
    files = Dir.glob('output/*/*.changes')
    files.each do |path|
      puts "# Include: #{path}"

      target = File.basename(File.dirname(path))
      dist, codename, *_ = target.split('-')

      run! %(reprepro -b repos/#{dist} --ignore=wrongdistribution include #{codename} #{path})
    end
  end
end