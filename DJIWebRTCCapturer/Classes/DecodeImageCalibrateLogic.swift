//
//  VideoPreviewerAdapter.swift
//  Michael Maier
//
//  Created by Michael Maier on 23/07/2021.
//  Copyright © 2021 Michael Maier. All rights reserved.
//

import WebRTC
import DJISDK
import DJIWidget

protocol DecodeImageCalibrateLogic: DJIImageCalibrateDelegate {
    var cameraName: String? { get set }
}

class DroneDecodeImageCalibrateLogic: NSObject, DecodeImageCalibrateLogic {
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
    private var _cameraName: String?
    
    private var calibrateNeeded = false
    private var calibrateStandAlone = false
    //data source info
    private let dataSourceInfo: [String: DJIImageCalibrateFilterDataSource.Type] = [
        DJICameraDisplayNameMavic2ZoomCamera: DJIMavic2ZoomCameraImageCalibrateFilterDataSource.self,
        DJICameraDisplayNameMavic2ProCamera: DJIMavic2ProCameraImageCalibrateFilterDataSource.self,
    ]
    //helper for calibration
    private var helper: DJIImageCalibrateHelper?
    //calibrate datasource
    private var dataSource: DJIImageCalibrateFilterDataSource?
    //camera work mode
    private var workMode: DJICameraMode = .unknown
    
    deinit {
        releaseHelper()
    }
    
    func releaseHelper() {
        dataSource = nil
        helper = nil
    }
    
}

extension DroneDecodeImageCalibrateLogic {
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
