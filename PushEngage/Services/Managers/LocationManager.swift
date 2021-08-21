//
//  LocationManager.swift
//  PushEngage
//
//  Created by Abhishek on 14/03/21.
//

import Foundation
import CoreLocation

struct LocationCoordinates: Codable {
    
    var latitude, longitude: Double
    var error: LocationError?
    
    enum LocationError: String, Codable {
        case failed
        case denied 
    }
}


class LocationManager: NSObject, CLLocationManagerDelegate, LocationInfoProtocol {
    
    private var locationManager: CLLocationManager?
    
    var locationInfoObserver = Variable<LocationCoordinates?>(nil)
    
    override init() {
        super.init()
        self.locationSetup()
    }
    
    private func locationSetup() {
        
        if Utility.isLocationPrivcyEnabled {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            locationManager?.distanceFilter = CLLocationDistanceMax
        } else {
            PELogger.debug(className: String(describing: LocationManager.self),
                           message: "Location privacy is not enabled by host application.")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard  let last = locations.last  else {
            return
        }
        let locationCoordinates = LocationCoordinates(latitude: last.coordinate.latitude,
                                                      longitude: last.coordinate.longitude)
        locationInfoObserver.value = locationCoordinates
        
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager?.startUpdatingLocation()
            PELogger.debug(className: String(describing: LocationManager.self),
                           message: "location services authorized.")
        case .denied:
            locationInfoObserver.value?.error = .denied
            PELogger.debug(className: String(describing: LocationManager.self),
                           message: "Location services denied")
        case .notDetermined, .restricted:
            PELogger.debug(className: String(describing: LocationManager.self),
                           message: "Location services notDetermined")
        @unknown default:
            PELogger.debug(className: String(describing: LocationManager.self),
                           message: "unknown")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationInfoObserver.value?.error = .failed
    }
}
