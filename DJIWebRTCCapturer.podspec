#
# Be sure to run `pod lib lint DJIWebRTCCapturer.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'DJIWebRTCCapturer'
  s.version          = '0.1.0'
  s.summary          = 'iOS Swift WebRTC camera capturer for DJI drones'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
The DJIWebRTCCapturer is an extension to an existing WebRTC project, based on iOS Swift.
It implements the RTCVideoCapturer protocol which adds a DJI drone video stream as localVideoSource to an existing peerConnection.
                       DESC

  s.homepage         = 'https://github.com/mmaier/DJIWebRTCCapturer'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mmaier' => 'm.maier@mmwebdesign.at' }
  s.source           = { :git => 'https://github.com/mmaier/DJIWebRTCCapturer.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = 'DJIWebRTCCapturer/Classes/**/*'

  s.dependency 'GoogleWebRTC'
  s.dependency 'DJI-SDK-iOS'
  s.dependency 'DJIWidget'  
end
