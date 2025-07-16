#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint otpless_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'otpless_headless_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Standalone SDK for Otpless Headless functionality.'
  s.description      = <<-DESC
  otpless_headless_flutter is a modern iOS SDK built for Flutter with Swift that provides Otpless' Headless capabilities. Get your user authentication sorted in just five minutes by integrating of Otpless sdk.
  DESC
  s.homepage         = 'https://github.com/otpless-tech/flutter-headless-sdk.git'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Otpless' => 'developer@otpless.com' }
  s.source           = { :git => 'https://github.com/otpless-tech/flutter-headless-sdk.git', :tag => s.version.to_s }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'OtplessBM/Core', '1.1.7'
  s.ios.deployment_target = '13.0'

  s.swift_versions = ['5.5']
end
