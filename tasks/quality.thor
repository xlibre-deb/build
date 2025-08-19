require_relative 'common'

class Quality < Thor
  desc 'check', 'Check code style and spelling'
  def check
    run! %(rubocop)
    run! %(typos)
  rescue RuntimeError
    exit 1
  end
end
