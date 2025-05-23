Pod::Spec.new do |spec|
  spec.name = "WaterfallGrid"
  spec.version = "1.1.0"
  spec.summary = "A waterfall grid layout view for SwiftUI."
  spec.homepage = "https://github.com/paololeonardi/WaterfallGrid"

  spec.license = { :type => "MIT", :file => "LICENSE" }

  spec.author = "Paolo Leonardi"
  spec.social_media_url = "https://twitter.com/paololeonardi"

  spec.ios.deployment_target = "14.0"
  spec.osx.deployment_target = "10.15"
  spec.watchos.deployment_target = "6.0"
  spec.tvos.deployment_target = "13.0"

  spec.swift_version = '5.9'

  spec.source = { :git => "https://github.com/paololeonardi/WaterfallGrid.git", :tag => "#{spec.version}" }

  spec.source_files = "Sources/**/*"

  spec.frameworks = "Foundation", "SwiftUI"
end
