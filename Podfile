# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'PushEngage' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!
  
  pod 'SwiftLint'
  
  target 'PushEngageTests' do
    # uncomment this line to use the local SDK dependency and comment out next line
    # pod 'PushEngage', :path => "<>/pushengage-ios-sdk"
    pod 'PushEngage'
  end
end
    
target 'PushNotificationDemo' do
      # uncomment this line to use the local SDK dependency and comment out next line
      # pod 'PushEngage', :path => "<>/pushengage-ios-sdk"
      pod 'PushEngage'
      
      post_install do |installer|
          installer.pods_project.targets.each do |target|
            target.build_configurations.each do |config|
              config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'NO'
          end
        end
      end
      
      target 'PushEngageNotificationExtension' do
        # uncomment this line to use the local SDK dependency and comment out next line
        # pod 'PushEngage', :path => "<>/pushengage-ios-sdk"
        pod 'PushEngage'
      end
        
      target 'PushEngageNotificationContentExtenstion' do
        # uncomment this line to use the local SDK dependency and comment out next line
        # pod 'PushEngage', :path => "<>/pushengage-ios-sdk"
        pod 'PushEngage'
      end
end

target 'PushNotificationObjcSample' do
      # uncomment this line to use the local SDK dependency and comment out next line
      # pod 'PushEngage', :path => "<>/pushengage-ios-sdk"
      pod 'PushEngage'
  
  target 'PushEngageObjcNotificationExtension' do
      # uncomment this line to use the local SDK dependency and comment out next line
      # pod 'PushEngage', :path => "<>/pushengage-ios-sdk"
      pod 'PushEngage'
  end
  
  target 'NotificationContentExtensionObjcSample' do
      # uncomment this line to use the local SDK dependency and comment out next line
      # pod 'PushEngage', :path => "<>/pushengage-ios-sdk"
      pod 'PushEngage'
  end
end


