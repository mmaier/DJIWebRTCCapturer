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
        
        self.adapter = VideoPreviewerAdapter.init()
        self.adapter?.delegate = self
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

// MARK: WebRTC Adapter

extension DroneCapturer {
    func didReceive(buffer: CVPixelBuffer) {
        print("Drone Capturer: Did receive buffer")
        let pixelBuffer = RTCCVPixelBuffer(pixelBuffer: buffer)
        guard let frame = videoFrameFor(pixelBuffer) else { return }
        print("Drone Capturer: Did generate frame \(frame.timeStampNs)")
        self.delegate?.capturer(self, didCapture: frame)
    }
    
    func videoFrameFor(_ buffer: RTCCVPixelBuffer)->RTCVideoFrame? {
        let nanoSeconds = Calendar.current.component(.nanosecond, from: Date())
        return RTCVideoFrame(buffer: buffer, rotation: RTCVideoRotation._0, timeStampNs: Int64(nanoSeconds))
    }
}

// MARK: Video Frame Processor

extension DroneCapturer: VideoFrameProcessor {
    
    public func videoProcessorEnabled() -> Bool {
        return true
    }
    
    public func videoProcessFrame(_ frame: UnsafeMutablePointer<VideoFrameYUV>!) {
        guard let buffer = frame.pointee.cv_pixelbuffer_fastupload else { return }
        let cvBuf = unsafeBitCast(buffer, to: CVPixelBuffer.self)
        self.didReceive(buffer: cvBuf)
    }
    
}

// MARK: Video Preview Adapter

class VideoPreviewerAdapter: NSObject {
    
    var delegate: VideoFrameProcessor?
    
    weak var previewer = DJIVideoPreviewer.instance()
    weak var feed = DJISDKManager.videoFeeder()?.primaryVideoFeed
    
    // lightbridge2
    var isEXTPortEnabled: Bool?
    var LBEXTPercent: Float?
    var HDMIAVPercent: Float?
    
    fileprivate var timer: Timer?
    fileprivate var isAircraft = false
    fileprivate var cameraMode: DJICameraMode = .unknown
    fileprivate var photoRatio: DJICameraPhotoAspectRatio = .ratioUnknown
    fileprivate var isLightbridge2 = false
    fileprivate var productName: String?
    fileprivate var cameraName: String?
    fileprivate var calibrateLogic = DecodeImageCalibrateLogic()
    
    override init() {
        super.init()
        previewer?.calibrateDelegate = calibrateLogic
        if g_loadPrebuildIframeOverrideFunc == nil {
            g_loadPrebuildIframeOverrideFunc = loadPrebuildIframePrivate
        }
    }
    
    convenience init(lightbridge2: Bool) {
        self.init()
        isLightbridge2 = lightbridge2
    }
    
    convenience init(videoPreviewer: DJIVideoPreviewer, with videoFeed: DJIVideoFeed) {
        self.init()
        previewer = videoPreviewer
        feed = videoFeed
    }
    
    func start() {
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.updateInfo), userInfo: nil, repeats: true)
        }
        DJISDKManager.videoFeeder()?.add(self)
        if feed != nil {
            feed?.add(self, with: nil)
        }
        if isLightbridge2 {
            listenToLightbridge2()
        }
        
        previewer?.enableHardwareDecode = true
        previewer?.enableFastUpload = true
        previewer?.registFrameProcessor(delegate)
        previewer?.start()
    }
    
    func stop() {
        DispatchQueue.main.async {
            if self.timer != nil {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
        if feed != nil {
            feed?.remove(self)
        }
        if isLightbridge2 {
            stopListenToLightbridge2()
        }
    }
    
    // For Mavic 2
    func setupFrameControlHandler() {
        previewer?.frameControlHandler = self
    }
    
    @objc fileprivate func updateInfo() {
        // 1. check if the product is still connecting
        guard previewer != nil,
            let product = DJISDKManager.product()
            
        else {
            return
        }
        
        // 2. Get product names and camera names
        productName = product.model
        if (productName == nil) {
            previewer!.encoderType = ._unknown
            previewer!.rotation = VideoStreamRotationType.default
            previewer!.contentClipRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            return;
        }
        isAircraft = product is DJIAircraft
        cameraName = VideoPreviewerAdapter.camera()?.displayName
        
        // Set decode type
        updateEncodeType()
        
        // 3. Get camera work mode
        guard let cameraModel = VideoPreviewerAdapter.camera() else { return }
        cameraModel.getModeWithCompletion { [weak self] (mode, error) in
            guard error == nil else { return }
            self?.cameraMode = mode
            self?.updateContentRect()
        }
        cameraModel.getPhotoAspectRatio { [weak self] (ratio, error) in
            guard error == nil else { return }
            self?.photoRatio = ratio
            self?.updateContentRect()
        }
        updateContentRect()
        calibrateLogic.cameraName = cameraModel.displayName
        
        if cameraModel.displayName == DJICameraDisplayNameMavicProCamera {
            cameraModel.getOrientationWithCompletion { [weak self] (orientation, error) in
                guard error == nil else { return }
                if orientation == .landscape {
                    self?.previewer?.rotation = .default
                } else {
                    self?.previewer?.rotation = .CW90
                }
            }
        }
    }
    
    
    fileprivate func updateEncodeType() {
        // Check if Inspire 2 FPV
        if feed?.physicalSource == DJIVideoFeedPhysicalSource.fpvCamera {
            previewer?.encoderType = ._1860_Inspire2_FPV
            return
        }
        
        // Check if Lightbridge 2
        if VideoPreviewerAdapter.isUsingLightbridge2(for: productName, aircraft: isAircraft, camera: cameraName) {
            previewer?.encoderType = ._LightBridge2
            return
        }
        
        let encodeType = VideoPreviewerAdapter.getDataSource(with: cameraName, aircraft: isAircraft)
        previewer?.encoderType = encodeType
    }
    
    fileprivate func updateContentRect() {
        if feed?.physicalSource == .fpvCamera {
            setDefaultContentRect()
            return
        }
        
        if cameraName == DJICameraDisplayNameXT {
            updateContentRectForXT()
            return
        }
        
        if cameraMode == .shootPhoto {
            updateContentRectInPhotoMode()
        } else {
            setDefaultContentRect()
        }
    }
    
    fileprivate func updateContentRectForXT() {
        // Workaround: when M100 is setup with XT, there are 8 useless pixels on
        // the left and right hand sides.
        if productName == DJIAircraftModelNameMatrice100 {
            previewer?.contentClipRect = CGRect(x: 0.010869565217391, y: 0, width: 0.978260869565217, height: 1)
        }
    }
    
    fileprivate func updateContentRectInPhotoMode() {
        var area = CGRect(x: 0, y: 0, width: 1, height: 1)
        var needFitToRate = false
        
        if cameraName == DJICameraDisplayNameX3 ||
            cameraName == DJICameraDisplayNameX5 ||
            cameraName == DJICameraDisplayNameX5R ||
            cameraName == DJICameraDisplayNamePhantom3ProfessionalCamera ||
            cameraName == DJICameraDisplayNamePhantom4Camera ||
            cameraName == DJICameraDisplayNameMavicProCamera {
            needFitToRate = true;
        }
        
        if needFitToRate && photoRatio != .ratioUnknown {
            var rateSize: CGSize
            
            switch (photoRatio) {
            case .ratio3_2:
                rateSize = CGSize(width: 3, height: 2)
            case .ratio4_3:
                rateSize = CGSize(width: 4, height: 3)
            default:
                rateSize = CGSize(width: 16, height: 9)
            }
            
            let streamRect = CGRect(x: 0, y: 0, width: 16, height: 9)
            let destRect = DJIVideoPresentViewAdjustHelper.aspectFit(withFrame: streamRect, size: rateSize)
            area = DJIVideoPresentViewAdjustHelper.normalizeFrame(destRect, withIdentityRect: streamRect)
        }
        
        if previewer?.contentClipRect != area {
            previewer?.contentClipRect = area
        }
    }
    
    fileprivate func setDefaultContentRect() {
        previewer?.contentClipRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

}

// MARK: Video Feed Listener

extension VideoPreviewerAdapter: DJIVideoFeedListener {
    
    func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData videoData: Data) {
        guard videoFeed == feed else {
            NSLog("ERROR: Wrong video feed update is received!");
            return
        }
        
        videoData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            let p = UnsafeMutablePointer<UInt8>.init(mutating: ptr)
            print("Video Feed Update: \(p)")
            previewer?.push(p, length: Int32(videoData.count))
            
        }
    }
    
}

// MARK: lightbridge2
extension VideoPreviewerAdapter {
    
    fileprivate func listenToLightbridge2() {
        guard let extEnabledKey = DJIAirLinkKey.init(index: 0, subComponent: DJIAirLinkLightbridgeLinkSubComponent, subComponentIndex: 0, andParam: DJILightbridgeLinkParamEXTVideoInputPortEnabled) else { return }
        let extValue = DJISDKManager.keyManager()?.getValueFor(extEnabledKey)
        
        DJISDKManager.keyManager()?.startListeningForChanges(on: extEnabledKey, withListener: self, andUpdate: { [weak self] (oldValue, newValue) in
            self?.isEXTPortEnabled = Bool(exactly: newValue?.value as! NSNumber) ?? false
            self?.updateVideoFeed()
        })
        isEXTPortEnabled = Bool(exactly: extValue?.value as! NSNumber) ?? false
        
        guard let LBPercentKey = DJIAirLinkKey.init(index: 0, subComponent: DJIAirLinkLightbridgeLinkSubComponent, subComponentIndex: 0, andParam: DJILightbridgeLinkParamBandwidthAllocationForLBVideoInputPort) else { return }
        let LBPercent = DJISDKManager.keyManager()?.getValueFor(LBPercentKey)
        DJISDKManager.keyManager()?.startListeningForChanges(on: LBPercentKey, withListener: self, andUpdate: { [weak self] (oldValue, newValue) in
            self?.LBEXTPercent = (newValue?.value as! NSNumber).floatValue
            self?.updateVideoFeed()
        })
        LBEXTPercent = (LBPercent?.value as! NSNumber).floatValue
        
        guard let HDMIPercentKey = DJIAirLinkKey.init(index: 0, subComponent: DJIAirLinkLightbridgeLinkSubComponent, subComponentIndex: 0, andParam: DJILightbridgeLinkParamBandwidthAllocationForHDMIVideoInputPort) else { return }
        let HDMIPercent = DJISDKManager.keyManager()?.getValueFor(HDMIPercentKey)
        DJISDKManager.keyManager()?.startListeningForChanges(on: HDMIPercentKey, withListener: self, andUpdate: { [weak self] (oldValue, newValue) in
            self?.HDMIAVPercent = (newValue?.value as! NSNumber).floatValue
            self?.updateVideoFeed()
        })
        HDMIAVPercent = (HDMIPercent?.value as! NSNumber).floatValue
        
        updateVideoFeed()
    }
    
    fileprivate func stopListenToLightbridge2() {
        DJISDKManager.keyManager()?.stopAllListening(ofListeners: self)
    }
    
    fileprivate func updateVideoFeed() {
        guard isEXTPortEnabled != nil else {
            swapToPrimaryVideoFeedIfNecessary()
            return
        }
        
        if isEXTPortEnabled == true {
            guard LBEXTPercent != nil else {
                swapToPrimaryVideoFeedIfNecessary()
                return
            }
            
            if LBEXTPercent!.isEqual(to: 1.0) {
                // All in primary source
                if !isUsingPrimaryVideoFeed() {
                    swapVideoFeed()
                }
            } else if LBEXTPercent!.isEqual(to: 0.0) {
                if isUsingPrimaryVideoFeed() {
                    swapVideoFeed()
                }
            }
        } else {
            guard HDMIAVPercent != nil else {
                swapToPrimaryVideoFeedIfNecessary()
                return
            }
            
            if HDMIAVPercent!.isEqual(to: 1.0) {
                // All in primary source
                if !isUsingPrimaryVideoFeed() {
                    swapVideoFeed()
                }
            } else if HDMIAVPercent!.isEqual(to: 0.0) {
                if isUsingPrimaryVideoFeed() {
                    swapVideoFeed()
                }
            }
        }
    }
    
    fileprivate func isUsingPrimaryVideoFeed() -> Bool {
        return feed == DJISDKManager.videoFeeder()?.primaryVideoFeed
    }
    
    fileprivate func swapVideoFeed() {
        previewer?.pause()
        feed?.remove(self)
        if isUsingPrimaryVideoFeed() {
            feed = DJISDKManager.videoFeeder()?.secondaryVideoFeed
        } else {
            feed = DJISDKManager.videoFeeder()?.primaryVideoFeed
        }
        feed?.add(self, with: nil)
        previewer?.safeResume()
    }
    
    fileprivate func swapToPrimaryVideoFeedIfNecessary() {
        if !isUsingPrimaryVideoFeed() {
            swapVideoFeed()
        }
    }
}

// MARK: delegate
extension VideoPreviewerAdapter: DJIVideoFeedSourceListener {
    func videoFeed(_ videoFeed: DJIVideoFeed, didChange physicalSource: DJIVideoFeedPhysicalSource) {
        guard videoFeed == feed else {
            return
        }
        if physicalSource == .unknown {
            NSLog("Video feed is disconnected. ")
        } else {
            updateEncodeType()
            updateContentRect()
        }
    }
    
    
}

extension VideoPreviewerAdapter: DJIVideoPreviewerFrameControlDelegate {
    func parseDecodingAssistInfo(withBuffer buffer: UnsafeMutablePointer<UInt8>!, length: Int32, assistInfo: UnsafeMutablePointer<DJIDecodingAssistInfo>!) -> Bool {
        return feed?.parseDecodingAssistInfo(withBuffer: buffer, length: length, assistInfo: assistInfo) ?? false
    }
    
    func decodingDidSucceed(withTimestamp timestamp: UInt32) {
        feed?.decodingDidSucceed(withTimestamp: UInt(timestamp))
    }
    
    func isNeedFitFrameWidth() -> Bool {
        let displayName = VideoPreviewerAdapter.camera()?.displayName
        if displayName == DJICameraDisplayNameMavic2ZoomCamera ||
            displayName == DJICameraDisplayNameMavic2ProCamera {
            return true
        }
        return false
    }
    
    func syncDecoderStatus(_ isNormal: Bool) {
        feed?.syncDecoderStatus(isNormal)
    }
    
    func decodingDidFail() {
        feed?.decodingDidFail()
    }
    
}

// MARK: helper
extension VideoPreviewerAdapter {
    fileprivate class func camera() -> DJICamera? {
        guard let product = DJISDKManager.product() else { return nil }
        if product is DJIAircraft || product is DJIHandheld {
            return product.camera
        } else {
            return nil
        }
    }
    
    fileprivate class func isUsingLightbridge2(for product: String?, aircraft: Bool, camera: String?) -> Bool {
        guard aircraft else { return false }
        
        if product == DJIAircraftModelNameA3 ||
            product == DJIAircraftModelNameN3 ||
            product == DJIAircraftModelNameMatrice600 ||
            product == DJIAircraftModelNameMatrice600Pro {
            return true
        }
        
        // Special case: can be stand-alone Lightbridge 2
        if product == DJIAircraftModelNameUnknownAircraft,
            camera == nil {
            return true;
        }
        
        return false;
    }
    
    fileprivate class func getDataSource(with camera: String?, aircraft: Bool) -> H264EncoderType {
        if camera == DJICameraDisplayNameX3 {
            if let cameraModel = VideoPreviewerAdapter.camera() {
                /**
                 *  Osmo's video encoding solution is changed since a firmware version.
                 *  X3 also began to support digital zoom since that version. Therefore,
                 *  `isDigitalZoomSupported` is used to determine the correct
                 *  encode type.
                 */
                if !aircraft && cameraModel.isDigitalZoomSupported() {
                    return ._A9_OSMO_NO_368
                } else {
                    return ._DM368_inspire
                }
            }
            
        } else if camera == DJICameraDisplayNameZ3 {
            return ._A9_OSMO_NO_368
        } else if camera == DJICameraDisplayNameX5 || camera == DJICameraDisplayNameX5R {
            return ._DM368_inspire
        } else if camera == DJICameraDisplayNamePhantom3ProfessionalCamera {
            return ._DM365_phamtom3x
        } else if camera == DJICameraDisplayNamePhantom3AdvancedCamera {
            return ._A9_phantom3s
        } else if camera == DJICameraDisplayNamePhantom3StandardCamera {
            return ._A9_phantom3c
        } else if camera == DJICameraDisplayNamePhantom4Camera {
            return ._1860_phantom4x
        } else if camera == DJICameraDisplayNameMavicProCamera {
            let product = DJISDKManager.product() as? DJIAircraft
            if product?.airLink?.wifiLink != nil {
                return ._1860_phantom4x;
            } else {
                return ._unknown
            }
        } else if camera == DJICameraDisplayNameSparkCamera {
            return ._1860_phantom4x
        } else if camera == DJICameraDisplayNameZ30 {
            return ._GD600
        } else if camera == DJICameraDisplayNamePhantom4ProCamera ||
            camera == DJICameraDisplayNamePhantom4AdvancedCamera ||
            camera == DJICameraDisplayNameX5S ||
            camera == DJICameraDisplayNameX4S ||
            camera == DJICameraDisplayNameX7 ||
            camera == DJICameraDisplayNamePayload {
            return ._H1_Inspire2
        } else if camera == DJICameraDisplayNameMavicAirCamera {
            return ._MavicAir
        }
        
        return ._unknown
    }
}

// MARK: Calibrate Logic

class DecodeImageCalibrateLogic: NSObject {
    var cameraName: String? {
        get {
            return _cameraName
        }
        set {
            guard newValue != _cameraName else {
                return
            }
            _cameraName = newValue
            let supported = _cameraName == DJICameraDisplayNameMavic2ZoomCamera || _cameraName == DJICameraDisplayNameMavic2ProCamera
            calibrateNeeded = supported
            calibrateStandAlone = false
        }
    }
    var cameraIndex = 0
    fileprivate var _cameraName: String?
    
    fileprivate var calibrateNeeded = false
    fileprivate var calibrateStandAlone = false
    //data source info
    fileprivate let dataSourceInfo: [String: DJIImageCalibrateFilterDataSource.Type] = [
        DJICameraDisplayNameMavic2ZoomCamera: DJIMavic2ZoomCameraImageCalibrateFilterDataSource.self,
        DJICameraDisplayNameMavic2ProCamera: DJIMavic2ProCameraImageCalibrateFilterDataSource.self,
    ]
    //helper for calibration
    fileprivate var helper: DJIImageCalibrateHelper?
    //calibrate datasource
    fileprivate var dataSource: DJIImageCalibrateFilterDataSource?
    //camera work mode
    fileprivate var workMode: DJICameraMode = .unknown
    
    deinit {
        releaseHelper()
    }
    
    func releaseHelper() {
        dataSource = nil
        helper = nil
    }
    
}

extension DecodeImageCalibrateLogic: DJIImageCalibrateDelegate {
    func shouldCreateHelper() -> Bool {
        return calibrateNeeded
    }
    
    func helperCreated() -> DJIImageCalibrateHelper? {
        if calibrateStandAlone {
            helper = DJIDecodeImageCalibrateHelper.init(shouldCreateCalibrateThread: false, andRenderThread: false)
        } else {
            helper = DJIImageCalibrateHelper.init(shouldCreateCalibrateThread: false, andRenderThread: false)
        }
        if !calibrateNeeded {
            return nil
        }
        return helper
    }
    
    func destroyHelper() {
        releaseHelper()
    }
    
    func calibrateDataSource() -> DJIImageCalibrateFilterDataSource? {
        guard _cameraName != nil else {
            return nil
        }
        
        if let targetClass = dataSourceInfo[_cameraName!],
            dataSource != nil,
            dataSource!.isKind(of: targetClass),
            dataSource!.workMode == workMode.rawValue {
            return dataSource
        } else {
            dataSource = (dataSourceInfo[_cameraName!] ?? DJIImageCalibrateFilterDataSource.self).instance(withWorkMode: workMode.rawValue)
            return dataSource
        }
    }
    
    
}
