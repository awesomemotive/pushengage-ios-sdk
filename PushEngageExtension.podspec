Pod::Spec.new do |spec|

  spec.name         = "PushEngageExtension"
  spec.version      = "1.0.0"
  spec.summary      = "Extension-safe core of the PushEngage iOS SDK."
  spec.description  = <<-DESC
    The extension-safe core of the PushEngage iOS SDK: notification payload
    parsing, rich-media attachment handling, delivery/click analytics, and the
    Notification Service / Content Extension entry points. Link this pod into
    your notification extension targets; link the `PushEngage` pod into your
    app target (it depends on this one).
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
  spec.source_files = "Sources/PushEngageExtension/**/*.{swift}"
  spec.swift_version = "5.9"
  spec.pod_target_xcconfig = { 'SWIFT_PACKAGE_NAME' => 'PushEngage' }
end
