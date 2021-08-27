Pod::Spec.new do |spec|

  spec.name         = "PushEngage"
  spec.version      = "0.0.1-beta"
  spec.summary      = "iOS Framework which provides easy way to start with Push
                       notification in you native iOS Applications."
  spec.description  = "To make your users interact your application even they are not using you application. Push Notifications plays most important role
                      our product will make this very easy for you to integrate with you new or existing applications."
  spec.homepage     = "https://github.com/awesomemotive/pushengage-ios-sdk"
  spec.license =  { :type => "MIT", :file => "LICENSE" }
  spec.author             = { "PushEngage" => "care@pushengage.com" }
  spec.platform = :ios
  spec.ios.deployment_target  = '9.0'
  spec.requires_arc = true
  spec.source = { :git => "https://github.com/awesomemotive/pushengage-ios-sdk.git",
                  :tag => "#{spec.version}"
                }
  spec.ios.framework = "UIKit"
  spec.dependency 'SwiftLint'
 # spec.vendored_frameworks = "Framework/PushEngage.framework"
  spec.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  spec.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  spec.source_files = "PushEngage/**/*.{swift}"
  spec.swift_version = "5.0"
end

