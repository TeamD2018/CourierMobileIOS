import UIKit
import Alamofire
import SwiftyJSON

import CoreLocation

enum ButtonStates {
    case CreateCourier
    case DeleteCourier
    case UpdateLocation
    case StopUpdate
}

struct Location {
    var lat: Float64
    var lon: Float64
}

struct Courier {

    var id: String?
    var name: String
    var phone: String?
    var location: Location?

    init(id: String? = nil, name: String, phone: String? = nil, location: Location? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.location = location
    }

    func toJSON() -> JSON {
        var j: [String: Any] = [
            "name": self.name
        ]
        if let phone = self.phone {
            j["phone"] = phone
        }
        if let id = self.id {
            j["id"] = id
        }
        if let location = self.location {
            j["location"] = location
        }
        return JSON(j)
    }

    init(j: JSON) {
        self.id = j["id"].string
        self.name = j["name"].string!
        self.phone = j["phone"].string
        self.location = Location(lat: j["location"].dictionary?["lat"]?.double ?? 0.0,
                lon: j["location"].dictionary?["lon"]?.double ?? 0.0)
    }
}

class ViewController: UIViewController {
    @IBOutlet weak var btnCreateCourier: UIButton!
    @IBOutlet weak var nameField: UITextField!
    @IBOutlet weak var phoneField: UITextField!
    @IBOutlet weak var log: UITextView!

    var defaultBtnColor: UIColor?
    
    @IBOutlet weak var courierInfoLabel: UILabel!

    var locationManager: CLLocationManager = CLLocationManager()
    var startLocation: CLLocation!

    var httpManage: SessionManager = {
        let serverTrustPolicies: [String: ServerTrustPolicy] = [
            "track-delivery.club": .disableEvaluation
        ]

        // Create custom manager
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = Alamofire.SessionManager.defaultHTTPHeaders
        let manager = Alamofire.SessionManager(
                configuration: URLSessionConfiguration.default,
                serverTrustPolicyManager: ServerTrustPolicyManager(policies: serverTrustPolicies)
        )

        return manager
    }()

    @IBOutlet weak var btnUpdateLocation: UIButton!

    var btnCreateCourierState: ButtonStates = .CreateCourier {
        didSet {
            switch btnCreateCourierState {
            case .CreateCourier:
                self.btnCreateCourier.setTitle("Создать курьера", for: .normal)
            case .DeleteCourier:
                self.btnCreateCourier.setTitle("Удалить курьера", for: .normal)
            default:
                break
            }

        }
    }

    var btnUpdateLocationState: ButtonStates = .UpdateLocation {
        didSet {
            switch btnUpdateLocationState {
            case .UpdateLocation:
                self.btnUpdateLocation.setTitle("Обновлять", for: .normal)
            case .StopUpdate:
                self.btnUpdateLocation.setTitle("СТОП", for: .normal)
            default:
                break
            }
        }
    }

    var courier: Courier?
    var store = UserDefaults.standard

    override func viewDidLoad() {
        super.viewDidLoad()
        self.defaultBtnColor = self.btnUpdateLocation.backgroundColor
        self.btnUpdateLocation.isEnabled = false
        self.btnUpdateLocation.backgroundColor = .lightGray
        if let courier_json = self.store.dictionary(forKey: "courier") {
            self.courier = Courier(j: JSON(courier_json))
            self.courierInfoLabel.text = "Your id: " + self.courier!.id!
            self.btnCreateCourierState = .DeleteCourier
            self.btnUpdateLocation.isEnabled = true
            self.btnUpdateLocation.backgroundColor = self.defaultBtnColor
        }
        self.btnUpdateLocationState = .UpdateLocation
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        startLocation = nil
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
//        locationManager.pausesLocationUpdatesAutomatically = true
        self.courierInfoLabel.text = ""
    }

    @IBAction func btnClickCreateCourier(_ sender: UIButton) {
        switch self.btnCreateCourierState {
        case .CreateCourier:
            if nameField.text!.isEmpty {
                courierInfoLabel.text = "Имя должно быть заполнено"
                return
            }
            self.courier = Courier(name: nameField.text!)
            if let phone = phoneField.text, !phone.isEmpty {
                self.courier!.phone = phone
            }
            let r = request("https://track-delivery.club/api/v1/couriers", method: .post, parameters: courier?.toJSON().dictionaryObject, encoding: JSONEncoding.default, headers: nil)
                    .validate(statusCode: 201...201)
                    .responseJSON { resp in
                        switch resp.result {
                        case .success:
                            let json = JSON(resp.result.value!)
                            if let id = json["id"].string {
                                self.courier!.id = id
                                self.courierInfoLabel.text = "Your id: " + json["id"].string!
                                self.nameField.text = ""
                                self.phoneField.text = ""
                                self.btnCreateCourierState = .DeleteCourier
                                self.btnUpdateLocation.isEnabled = true
                                self.btnUpdateLocation.backgroundColor = self.defaultBtnColor
                                self.store.set(self.courier?.toJSON().dictionaryObject, forKey: "courier")
                                print(json)
                            }
                        case .failure(_):
                            self.courierInfoLabel.text = resp.result.value as? String
                        }

                    }
            debugPrint(r)
            debugPrint(courier!.toJSON().dictionaryObject!)
        case .DeleteCourier:
            request("https://track-delivery.club/api/v1/couriers/" + self.courier!.id!, method: .delete)
                    .validate(statusCode: 204...204)
                    .responseData { resp in
                        switch resp.result {
                        case .failure(let error):
                            self.courierInfoLabel.text = error.localizedDescription
                        case .success(_):
                            self.courierInfoLabel.text = "Курьер успешно удален"
                            self.btnCreateCourierState = .CreateCourier
                            self.btnUpdateLocation.isEnabled = false
                            self.btnUpdateLocation.backgroundColor = .lightGray
                            self.store.removeObject(forKey: "courier")
                        }
                    }
        default:
            break
        }
    }

    @IBAction func btnUpdateLocationClicked(_ sender: Any) {
        print(btnUpdateLocationState)
        switch btnUpdateLocationState {
        case .UpdateLocation:
            locationManager.requestAlwaysAuthorization()
            locationManager.startUpdatingLocation()
            btnUpdateLocationState = .StopUpdate
        case .StopUpdate:
            locationManager.stopUpdatingLocation()
            btnUpdateLocationState = .UpdateLocation
        default:
            break
        }
    }
}

extension ViewController: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let f = DateFormatter()
        f.dateFormat = "dd/MM hh:mm:ss"
        let d = f.string(from: Date())
        for l in locations {
            let c = l.coordinate
            let logStr = String(format: "[%@] lat: %.6f lon: %.6f\n", d, c.latitude, c.longitude)
            self.log.text.append(logStr)
            print(logStr)
        }
        let c = locations[locations.count-1].coordinate
        let r = request("https://track-delivery.club/api/v1/couriers/" + courier!.id!, method: .put,
                parameters: ["location": ["point": ["lat": c.latitude, "lon": c.longitude]]],
                encoding: JSONEncoding.default)
                .validate(statusCode: 200...200)
                .responseString { response in debugPrint(response.value ?? "nil") }
        
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    }

    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    }

    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
    }

    public func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error.localizedDescription)
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    }

    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }

    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
    }

    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
    }

    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
    }

    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    }
}
