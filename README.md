# DJIWebRTCCapturer

iOS Swift WebRTC camera capturer for DJI drones.
The DJIWebRTCCapturer is an extension to an existing WebRTC project, based on iOS Swift.
It implements the RTCVideoCapturer protocol which adds a DJI drone video stream as localVideoSource to an existing peerConnection.

As of now the capturer only supports hardware decoding.

## Installation

DJIWebRTCCapturer is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'DJIWebRTCCapturer'
```

and run `pod install` from the project directory.

## Usage

Before implementing the DroneCapturer, a working WebRTC connection plus a successfully connected DJI device is necessary. The DroneCapturer does not handle product connection / disconnection. To connect a drone, you need to implement the  `DJISDKManager.startConnectionToProduct()` method.

```swift
import DJIWebRTCCapturer

// use DroneCapturer instead of RTCCameraVideoCapturer
let droneCapturer = DroneCapturer(delegate: localVideoSource)

// a drone video view is necessary to decode the video frames 
let localDroneVideoView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
view.addSubview(localDroneVideoView)

// after local media stream has been initialized:
droneCapturer.startCapture(localDroneVideoView)

// stop capturing
droneCapturer.stopCapture()
```

## Author

Michael Maier

## License

DJIWebRTCCapturer is available under the MIT license. See the LICENSE file for more info.
