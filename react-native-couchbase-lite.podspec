# react-native-couchbase-lite.podspec

require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-couchbase-lite"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  react-native-couchbase-lite
                   DESC
  s.homepage     = "https://github.com/oneok-mobile/react-native-couchbase-lite"
  s.license      = "MIT"
  s.authors      = { "Jordan Alcott" => "jordan.alcott@oneok.com" }
  s.platforms    = { :ios => "9.0" }
  s.source       = { :git => "https://github.com/oneok-mobile/react-native-couchbase-lite.git", :tag => "#{s.version}" }
  s.frameworks   = "CouchbaseLiteSwift";
  s.vendored_frameworks = "CouchbaseLiteSwift.xcframework"
  s.pod_target_xcconfig = {
    "FRAMEWORK_SEARCH_PATHS": "\"$(SRCROOT)/../../node_modules/react-native-couchbase-lite/ios/Frameworks/**\"",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => "CBLCOMMUNITY",
  }

  s.source_files = "ios/**/*.{h,c,cc,cpp,m,mm,swift}"
  s.exclude_files = ["ios/Frameworks/**/*"]
  s.requires_arc = true

  s.dependency "React"

end

