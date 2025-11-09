import Foundation
import WeatherKit
import CoreLocation
import Combine
import MapKit

@MainActor
final class HomeWeatherProvider: NSObject, ObservableObject {
    struct WeatherSummary {
        let locationName: String?
        let temperatureText: String
        let conditionText: String
        let symbolName: String
    }

    @Published private(set) var summary: WeatherSummary?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isLoading = false

    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()

    private var authorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14.0, macOS 11.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        guard CLLocationManager.locationServicesEnabled() else {
            statusMessage = "Turn on Location Services to see the local weather."
            summary = nil
            isLoading = false
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            statusMessage = nil
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            statusMessage = "Location access is required to show local weather."
            summary = nil
            isLoading = false
        case .authorizedAlways, .authorizedWhenInUse:
            statusMessage = nil
            requestWeather()
        @unknown default:
            statusMessage = nil
        }
    }

    private func requestWeather() {
        if let location = locationManager.location {
            fetchWeather(for: location)
        } else {
            isLoading = true
#if os(macOS)
            locationManager.startUpdatingLocation()
#endif
            locationManager.requestLocation()
        }
    }

    private func fetchWeather(for location: CLLocation) {
        isLoading = true

        Task {
            do {
                let weather = try await weatherService.weather(for: location)
                let locationName = await resolveLocationName(for: location)
                let temperatureText = weather.currentWeather.temperature.formatted(.measurement(width: .abbreviated, usage: .weather))
                let conditionText = weather.currentWeather.condition.description
                let symbolName = weather.currentWeather.symbolName
                let summary = WeatherSummary(
                    locationName: locationName,
                    temperatureText: temperatureText,
                    conditionText: conditionText.capitalized,
                    symbolName: symbolName
                )

                await MainActor.run {
                    self.summary = summary
                    self.statusMessage = nil
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Unable to load weather right now."
                    self.isLoading = false
                }
            }
        }
    }

    private func resolveLocationName(for location: CLLocation) async -> String? {
        // Prefer MapKit-based lookup to avoid deprecated CLGeocoder
        // Strategy: Run a local search near the coordinate with a broad query to find the most relevant nearby place/city
        // Then construct a friendly name from the MKPlacemark fields.
        let coordinate = location.coordinate
        let span = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        let region = MKCoordinateRegion(center: coordinate, span: span)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = nil // broad search
        request.region = region

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            // Prefer the first result; fall back to using an MKPlacemark made from the coordinate
            let placemark: MKPlacemark? = response.mapItems.first?.placemark ?? MKPlacemark(coordinate: coordinate)

            if let locality = placemark?.locality, let admin = placemark?.administrativeArea, !locality.isEmpty {
                return "\(locality), \(admin)"
            }

            if let locality = placemark?.locality, !locality.isEmpty {
                return locality
            }

            if let name = placemark?.name, !name.isEmpty {
                return name
            }

            return nil
        } catch {
            // If the search fails, try a lightweight fallback using MKPlacemark from the coordinate
            let fallbackPlacemark = MKPlacemark(coordinate: coordinate)
            if let locality = fallbackPlacemark.locality, let admin = fallbackPlacemark.administrativeArea, !locality.isEmpty {
                return "\(locality), \(admin)"
            }
            if let locality = fallbackPlacemark.locality, !locality.isEmpty {
                return locality
            }
            if let name = fallbackPlacemark.name, !name.isEmpty {
                return name
            }
            return nil
        }
    }
}

extension HomeWeatherProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.fetchWeather(for: location)
#if os(macOS)
            self.locationManager.stopUpdatingLocation()
#endif
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusMessage = "Unable to determine your location."
            self.isLoading = false
#if os(macOS)
            self.locationManager.stopUpdatingLocation()
#endif
        }
    }
}
