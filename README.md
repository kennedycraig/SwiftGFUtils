# SwiftGFUtils
An implementation of the Firebase GFUtils in Swift.

This class is a direct reimplementation of the Firebase GeoFire GFUtils functionality in Swift. This class allows you to break the dependency of the current GeoFire implementation, which appears unsupported, from the Firebase version <9.0.0.

The class is a singleton with one static member geoHashUtils and exposes three public functions which are symmetric to the originally defined GFUtils functions:
1. getGeoHash(location: CLLocation, precision: Int=GF_DEFAULT_PRECISION)->String
2. distanceFromLocation(startLocation: CLLocation, endLocation: CLLocation) -> Double
3. queryBoundsForLocation(location: CLLocationCoordinate2D, radius: Double) -> [GeoHashPair]


## Functions
### getGeoHash
getGeoHash accepts a location and precision(default 10) and returns a geoHash string according to this geoHash algorithm
https://en.wikipedia.org/wiki/Geohash.

### distanceFromLocation
distanceFromLocation accepts to CLLocation objects and returns a distance in meters.

### queryBoundsForLocation
queryBoundsForLocation accepts a CLLocationCoordinate2d and a radius in meters and returns a unique array of GeoHashPair which gives neighboring geoHashes within the location radius.

```
typealias GFGeoHash = String

struct GeoHashPair: Hashable {
    var id: UUID = UUID()
    var startValue: GFGeoHash
    var endValue: GFGeoHash
}
```

##Usage

```
import SwiftGFUtils

let lat = 40.56230175831099
let lon = -74.5975943979423
let miles = Measurement<UnitLength>(value: 3, unit: .miles)
let meters = miles.converted(to: .meters).value

let geoHashString = GeoHashUtils.geoHashUtils.getGeoHash(location: CLLocation(latitude: lat, longitude: lon), precision: 10)

let geoHashPairs = GeoHashUtils.geoHashUtils.queryBoundsForLocation(            CLLocationCoordinate2D(latitude: lat, longitude: lon), radius: meters)
```
