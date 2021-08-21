# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'PushEngage' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!
  
  pod 'SwiftLint'
  
  target 'PushEngageTests' do
    pod 'PushEngage', :path => "/Users/abhishek/Desktop/Public-repo/pushengage-ios-sdk"
  end
end
    
target 'PushNotificationDemo' do
      pod 'PushEngage', :path => "/Users/abhishek/Desktop/Public-repo/pushengage-ios-sdk"
      
      post_install do |installer|
          installer.pods_project.targets.each do |target|
            target.build_configurations.each do |config|
              config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'NO'
          end
        end
      end
      
      target 'PushEngageNotificationExtension' do
              pod 'PushEngage', :path => "/Users/abhishek/Desktop/Public-repo/pushengage-ios-sdk"
      end
        
      target 'PushEngageNotificationContentExtenstion' do
              pod 'PushEngage', :path => "/Users/abhishek/Desktop/Public-repo/pushengage-ios-sdk"
      end
end

target 'PushNotificationObjcSample' do
  pod 'PushEngage', :path => "/Users/abhishek/Desktop/Public-repo/pushengage-ios-sdk"
  
  target 'PushEngageObjcNotificationExtension' do
    pod 'PushEngage', :path => "/Users/abhishek/Desktop/Public-repo/pushengage-ios-sdk"
  end
end


