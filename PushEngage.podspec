Pod::Spec.new do |spec|

  spec.name         = "PushEngage"
  spec.version      = "1.0.0"
  spec.summary      = "iOS framework to support APNs Services PushEngage."
  spec.description  = <<-DESC
    PushEngage iOS SDK adds Apple Push Notification support to your app:
    subscriber management, rich notifications (images, deep links, custom
    sounds), action buttons, and click/view analytics integrated with the
    PushEngage dashboard. Add this pod to your app target; add the companion
    `PushEngageExtension` pod to your Notification Service / Content Extension
    targets.
  DESC
  spec.homepage     = "https://github.com/awesomemotive/pushengage-ios-sdk.git"
  spec.license =  { :type => "MIT", :file => "LICENSE" }
  spec.author  = { "PushEngage" => "care@pushengage.com" }
  spec.platform = :ios
  spec.ios.deployment_target  = '12.0'
  spec.requires_arc = true
  spec.source = { :git => "https://github.com/awesomemotive/pushengage-ios-sdk.git",
                  :tag => "#{spec.version}"
                }
  spec.ios.framework = "UIKit"
  spec.source_files = "Sources/PushEngage/**/*.{swift}"
  spec.swift_version = "5.9"
  spec.pod_target_xcconfig = { 'SWIFT_PACKAGE_NAME' => 'PushEngage' }

  spec.dependency 'PushEngageExtension', spec.version.to_s
end
