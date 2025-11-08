import Foundation
import WeatherKit
import CoreLocation

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

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        switch locationManager.authorizationStatus {
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
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: nil)
                    return
                }

                if let locality = placemark.locality, let admin = placemark.administrativeArea {
                    continuation.resume(returning: "\(locality), \(admin)")
                    return
                }

                if let locality = placemark.locality {
                    continuation.resume(returning: locality)
                    return
                }

                if let name = placemark.name {
                    continuation.resume(returning: name)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}

extension HomeWeatherProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.fetchWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusMessage = "Unable to determine your location."
            self.isLoading = false
        }
    }
}
