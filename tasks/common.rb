require 'bundler/inline'
gemfile do
  source 'https://rubygems.org'
  gem 'csv'
end

require 'singleton'
require 'csv'

module MatrixData
  def without_disabled
    reject { |_k, v| v[:disabled] == true }.extend(MatrixData)
  end

  def targets
    flat_map do |dist, body|
      body[:codenames].product(body[:arch]).map do |codename, arch|
        { dist:, codename:, arch: }
      end
    end
  end

  def target_names
    targets.map { |v| v.to_h.values.join('-') }
  end

  def to_yaml
    yaml = stringify(self).to_yaml
    yaml = yaml.gsub(/\A---\s*\n/, '') # remove header
    yaml.gsub(/^( *)-/, '\1  -') # indent array
  end

  private

  def stringify(hash)
    hash.to_h do |k, v|
      [k.to_s, v.is_a?(Hash) ? stringify(v) : v]
    end
  end
end

module PackagesData
end

class String
  def normalize_codename
    split.first.downcase
  end

  def excluded_codename?(dist)
    exclude = config.matrix[dist][:vars][:exclude]
    !exclude.nil? && exclude.include?(self)
  end

  def compatible_version?(dist)
    minver = config.matrix[dist][:vars][:min_version].to_s
    return true if minver.nil?
    minver = Gem::Version.new(minver)
    thisver = Gem::Version.new(delete_suffix(' LTS'))
    thisver >= minver
  end

  def ellipsize(max_length, keep_tail: false)
    return self if length <= max_length
    truncated_length = max_length - 3
    return '' if truncated_length <= 0
    if keep_tail
      '...' + self[-truncated_length..]
    else
      self[0...truncated_length] + '...'
    end
  end

  def command?
    system 'which', self, out: File::NULL, err: :out
  end

  # Mangles version string according to DEP-14.
  def mangle
    tr(':~', '%_').gsub(/\.(?=\.|$|lock$)/, '.#')
  end

  # Reverts DEP-14 mangled version back to original Debian version.
  def demangle
    tr('%_', ':~').gsub('#', '')
  end
end

class Config
  include Singleton

  def matrix
    if @matrix.nil?
      @matrix = YAML.load_file('matrix.yaml', symbolize_names: true)
      @matrix.extend(MatrixData)
    end
    @matrix
  end

  def packages
    if @packages.nil?
      @packages = YAML.load_file('packages.yaml', symbolize_names: true)
      @packages.extend(PackagesData)
    end
    @packages
  end
end

def config
  Config.instance
end

def run!(*)
  system(*, exception: true)
end

def key_fingerprint
  if !File.exist?('misc/key.asc')
    raise "Missing file 'misc/key.asc'"
  end
  text = %x(gpg --show-keys --with-colons misc/key.asc)
  rows = CSV.parse(text, col_sep: ':').reverse
  rows.each_with_index do |row, idx|
    type = row[0]
    next unless ['pub', 'sub'].include?(type)
    usage = row[11]
    next unless usage.include?('s') || usage.include?('S')
    fp = rows[idx-1][9]
    return fp
  end
  raise 'No signing key found in misc/key.asc'
end

def user_signingkey
  key = %x(git config --local user.signingkey)
  key = %x(git config --global user.signingkey) if $?.exitstatus != 0
  raise 'Git user signingkey not configured.' if $?.exitstatus != 0
  key.strip
end

def require_commands!(*commands)
  commands.flatten.each do |cmd|
    abort "Command '#{cmd}' not found" unless cmd.to_s.command?
  end
end
