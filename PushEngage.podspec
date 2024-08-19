Pod::Spec.new do |spec|

  spec.name         = "PushEngage"
  spec.version      = "0.0.4"
  spec.summary      = "iOS framework to support APNs Services PushEngage."
  spec.description  = "Provide the feature for Apple push notification."
  spec.homepage     = "https://github.com/awesomemotive/pushengage-ios-sdk.git"
  spec.license =  { :type => "MIT", :file => "LICENSE" }
  spec.author  = { "PushEngage" => "care@pushengage.com" }
  spec.platform = :ios
  spec.ios.deployment_target  = '9.0'
  spec.requires_arc = true
  spec.source = { :git => "https://github.com/awesomemotive/pushengage-ios-sdk.git",
                  :tag => "#{spec.version}"
                }
  spec.ios.framework = "UIKit"
  #spec.vendored_frameworks = "Framework/PushEngage.framework"
  spec.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  spec.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  spec.source_files = "Sources/PushEngage/**/*.{swift}"
  spec.swift_version = "5.0"
end

