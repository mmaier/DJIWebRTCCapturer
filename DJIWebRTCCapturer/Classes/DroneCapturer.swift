//
//  DroneCapturer.swift
//  Michael Maier
//
//  Created by Michael Maier on 23/07/2021.
//  Copyright © 2021 Michael Maier. All rights reserved.
//

import WebRTC
import DJISDK
import DJIWidget

open class DroneCapturer: RTCVideoCapturer {
    
    private var frameProcessor: VideoFrameProcessor?
    private var adapter: VideoPreviewerAdapter?
    private var localVideoView: UIView? {
        didSet {
            if localVideoView == nil {
                DJIVideoPreviewer.instance()?.unSetView()
            } else {
                DJIVideoPreviewer.instance()?.setView(localVideoView)
            }
        }
    }
    
    public override init() {
        super.init()
        self.frameProcessor = DroneVideoFrameProcessor(capturer: self)
    }
                
    open func startCapture(_ localVideoView: UIView) {
        print("Drone Capturer: Start")
        guard let camera = DJISDKManager.product()?.camera else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
                self.startCapture(localVideoView)
            })
            return
        }
        
        self.localVideoView = localVideoView
        camera.setMode(.shootPhoto, withCompletion: nil)
        
        self.adapter = DroneVideoPreviewerAdapter()
        self.adapter?.delegate = frameProcessor
        self.adapter?.start()
        
        if camera.displayName == DJICameraDisplayNameMavic2ZoomCamera ||
            camera.displayName == DJICameraDisplayNameMavic2ProCamera {
            self.adapter?.setupFrameControlHandler()
        }
    }
    
    open func stopCapture() {
        print("Drone Capturer: Stop")
        self.localVideoView = nil
        self.adapter?.stop()
        self.adapter = nil
    }
}

