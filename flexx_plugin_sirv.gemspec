Gem::Specification.new do |s|
  s.name        = "flexx_plugin_sirv"
  s.version     = "0.0.1"
  s.authors     = ["Paulo Henrique Castro"]
  s.email       = ["phlcastro@gmail.com"]
  s.homepage    = ""
  s.summary     = ": Summary of FlexxPluginSirv."
  s.description = ": Description of FlexxPluginSirv."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 4.2.10"
  s.add_dependency "mime-types"

  s.add_development_dependency "sqlite3"
end
