Pod::Spec.new do |spec|

  spec.name         = "PushEngage"
  spec.version      = "0.1.0"
  spec.summary      = "iOS framework to support APNs Services PushEngage."
  spec.description  = <<-DESC
    PushEngage iOS SDK adds Apple Push Notification support to your app:
    subscriber management, rich notifications (images, deep links, custom
    sounds), action buttons, and click/view analytics integrated with the
    PushEngage dashboard.
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
  spec.swift_version = "5.0"

  # When a consumer's extension target sets APPLICATION_EXTENSION_API_ONLY=YES
  # (default for notification service / content extensions), expose the matching
  # Swift compilation condition so the SDK can `#if !APPLICATION_EXTENSION_API_ONLY`
  # guard extension-unsafe code paths (UIApplication.shared etc).
  spec.pod_target_xcconfig = {
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) $(PE_EXT_API_ONLY_CONDITION_$(APPLICATION_EXTENSION_API_ONLY))',
    'PE_EXT_API_ONLY_CONDITION_YES' => 'APPLICATION_EXTENSION_API_ONLY'
  }
end

