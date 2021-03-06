# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name               = %q{mcrt}
  s.version            = '1.14.0'
  s.platform           = Gem::Platform::RUBY

  s.authors            = ['Peter Donald']
  s.email              = %q{peter@realityforge.org}

  s.homepage           = %q{https://github.com/realityforge/mcrt}
  s.summary            = %q{Maven Central Release Tool.}
  s.description        = %q{Maven Central Release Tool.}

  s.files              = `git ls-files`.split("\n")
  s.test_files         = `git ls-files -- {spec}/*`.split("\n")
  s.executables        = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths      = %w(lib)

  s.rdoc_options       = %w(--line-numbers --inline-source --title mcrt)
end
