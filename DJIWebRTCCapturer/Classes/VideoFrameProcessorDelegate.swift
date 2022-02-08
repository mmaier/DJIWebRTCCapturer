//
//  VideoFrameProcessorDelegate.swift
//  Michael Maier
//
//  Created by Michael Maier on 23/07/2021.
//  Copyright © 2021 Michael Maier. All rights reserved.
//

import WebRTC
import DJISDK
import DJIWidget

class DroneVideoFrameProcessor: NSObject, VideoFrameProcessor {
    
    private var capturer: RTCVideoCapturer
    
    init(capturer: RTCVideoCapturer) {
        self.capturer = capturer
    }
    
    // MARK: WebRTC Adapter

    func didReceive(buffer: CVPixelBuffer) {
        print("Drone Capturer: Did receive buffer")
        let pixelBuffer = RTCCVPixelBuffer(pixelBuffer: buffer)
        guard let frame = videoFrameFor(pixelBuffer) else { return }
        print("Drone Capturer: Did generate frame \(frame.timeStampNs)")
        capturer.delegate?.capturer(capturer, didCapture: frame)
    }
    
    func videoFrameFor(_ buffer: RTCCVPixelBuffer)->RTCVideoFrame? {
        let nanoSeconds = Calendar.current.component(.nanosecond, from: Date())
        return RTCVideoFrame(buffer: buffer, rotation: RTCVideoRotation._0, timeStampNs: Int64(nanoSeconds))
    }

    // MARK: Video Frame Processor
    
    public func videoProcessorEnabled() -> Bool {
        return true
    }
    
    public func videoProcessFrame(_ frame: UnsafeMutablePointer<VideoFrameYUV>!) {
        guard let buffer = frame.pointee.cv_pixelbuffer_fastupload else { return }
        let cvBuf = unsafeBitCast(buffer, to: CVPixelBuffer.self)
        didReceive(buffer: cvBuf)
    }
    
}
