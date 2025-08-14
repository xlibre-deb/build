module MatrixData
  def without_disabled
    self.select { |k, v| v[:disabled] != true }.extend(MatrixData)
  end

  def targets
    self.flat_map do |dist, body|
      body[:codenames].product(body[:arch]).map do |codename, arch|
        { dist:, codename:, arch: }
      end
    end
  end

  def target_names
    self.targets.map { |v| "#{v.to_h.values.join('-')}" }
  end

  def to_yaml
    yaml = stringify(self).to_yaml
    yaml.gsub!(/\A---\s*\n/, '') # remove header
    yaml.gsub!(/^( *)-/, '\1  -') # indent array
    yaml
  end

  private
  def stringify(hash)
    hash.map do |k, v|
      [k.to_s, v.is_a?(Hash) ? stringify(v) : v]
    end.to_h
  end
end

class String
  def normalize_codename
    self.split.first.downcase
  end

  def excluded_codename?(dist)
    exclude = matrix[dist][:vars][:exclude]
    !exclude.nil? && exclude.include?(self)
  end

  def compatible_version?(dist)
    minver = matrix[dist][:vars][:min_version].to_s
    return true if minver.nil?
    minver = Gem::Version.new(minver)
    thisver = Gem::Version.new(self.delete_suffix(' LTS'))
    thisver >= minver
  end
end

def matrix
  if $matrix.nil?
    $matrix = YAML.load_file('matrix.yaml', symbolize_names: true)
    $matrix.extend(MatrixData)
  end
  $matrix
end

def run!(*args)
  system(*args, exception: true)
end