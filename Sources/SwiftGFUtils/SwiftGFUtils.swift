//
//  GeohashUtils.swift
//  geoFireTesting
//
//  Created by Craig Kennedy on 1/1/23.
//

import Foundation
import CoreLocation
import MapKit
import SwiftUI

typealias GFGeoHash = String

struct GeoHashPair: Hashable {
    var id: UUID = UUID()
    var startValue: GFGeoHash
    var endValue: GFGeoHash
}

class GeoHashUtils {
    
    
    let METERS_PER_DEGREE_LATITUDE = Double(110574)
    let BITS_PER_GEOHASH_CHAR: UInt = 5
    let BITS_PER_BASE32_CHAR: UInt = 5
    static let GF_DEFAULT_PRECISION: Int = 10
    static let GF_MAX_PRECISION: UInt = 22
    

    // The equatorial circumference of the earth in meters
    let EARTH_MERIDIONAL_CIRCUMFERENCE = Double(40007860)

    // The equatorial radius of the earth in meters
    let EARTH_EQ_RADIUS = Double(6378137)
    // The following value assumes a polar radius of r_p = 6356752.3 and an equatorial radius of r_e = 6378137
    // The value is calculated as e2 == (r_e^2 - r_p^2)/(r_e^2)
    // The exact value is to avoid rounding errors
    let E2 = Double(0.00669447819799)
    // These are the 32 bit characters for Geohash characters
    private static let values = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    
    private init(){
        // Restrict creation outside the class
    }
    
    static let geoHashUtils = GeoHashUtils()

    func queryBoundsForLocation(location: CLLocationCoordinate2D, radius: Double) -> [GeoHashPair] {
        var queryBounds: [GeoHashPair] = []
        let queries = queriesForLocation(center: location, radius: radius)
        for query in queries {
            let bounds = boundsWithStartValue(startValue: query.startValue, endValue: query.endValue)
            queryBounds.append(bounds)
        }
        return queryBounds
    }
    
    func getGeoHash(location: CLLocation, precision: Int=GF_DEFAULT_PRECISION)->String{
        return newWithLocation(coordinate: location.coordinate, precision: UInt(precision))
    }
    
    func distanceFromLocation(startLocation: CLLocation, endLocation: CLLocation) -> Double {
        return endLocation.distance(from: startLocation)
    }
    
    private func boundsWithStartValue(startValue: GFGeoHash, endValue: GFGeoHash)->GeoHashPair{
        return initWithStartValue(startValue: startValue, endValue: endValue)
    }
    
    private func queriesForLocation(center: CLLocationCoordinate2D, radius: Double)->[GeoHashPair]{
        let latitudeDelta:CLLocationDegrees = radius/METERS_PER_DEGREE_LATITUDE
        let latitudeNorth:CLLocationDegrees = fmin(90, center.latitude + latitudeDelta)
        let latitudeSouth:CLLocationDegrees = fmax(-90, center.latitude - latitudeDelta)
        let longitudeDeltaNorth:CLLocationDegrees = toLongitudeDegreesAtLatitude(distance: radius, latitude: latitudeNorth)
        let longitudeDeltaSouth:CLLocationDegrees = toLongitudeDegreesAtLatitude(distance: radius, latitude: latitudeSouth)
        let longitudeDelta:CLLocationDegrees = fmax(longitudeDeltaNorth, longitudeDeltaSouth)
        let region: MKCoordinateRegion = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta*2, longitudeDelta: longitudeDelta*2))
        
        return queriesForRegion(region: region)
    }
    
    private func queriesForRegion(region: MKCoordinateRegion)->[GeoHashPair]{
        let bits: UInt = bitsForRegion(region: region)
        let geoHashPrecision: UInt = ((bits-1)/BITS_PER_GEOHASH_CHAR)+1

        var queries: [GeoHashPair] = []

        let latitudeCenter: CLLocationDegrees = region.center.latitude
        let latitudeNorth: CLLocationDegrees = region.center.latitude + region.span.latitudeDelta/2
        let latitudeSouth: CLLocationDegrees = region.center.latitude - region.span.latitudeDelta/2
        let longitudeCenter: CLLocationDegrees = region.center.longitude
        let longitudeWest: CLLocationDegrees = wrapLongitude(longitude: region.center.longitude - region.span.longitudeDelta/2)
        let longitudeEast: CLLocationDegrees = wrapLongitude(longitude: region.center.longitude + region.span.longitudeDelta/2 )

        queries.append(addQuery(lat: latitudeCenter, lon: longitudeCenter, precision: geoHashPrecision, bits: bits))
        queries.append(addQuery(lat: latitudeCenter, lon: longitudeEast, precision: geoHashPrecision, bits: bits))
        queries.append(addQuery(lat: latitudeCenter, lon: longitudeWest, precision: geoHashPrecision, bits: bits))

        queries.append(addQuery(lat: latitudeNorth, lon: longitudeCenter, precision: geoHashPrecision, bits: bits))
        queries.append(addQuery(lat: latitudeNorth, lon: longitudeEast, precision: geoHashPrecision, bits: bits))
        queries.append(addQuery(lat: latitudeNorth, lon: longitudeWest, precision: geoHashPrecision, bits: bits))

        queries.append(addQuery(lat: latitudeSouth, lon: longitudeCenter, precision: geoHashPrecision, bits: bits))
        queries.append(addQuery(lat: latitudeSouth, lon: longitudeEast, precision: geoHashPrecision, bits: bits))
        queries.append(addQuery(lat: latitudeSouth, lon: longitudeWest, precision: geoHashPrecision, bits: bits))
        
        return joinQueries(queries: queries)
        
    }
    
    private func joinQueries(queries: [GeoHashPair])->[GeoHashPair]{
        var joinedQueries: [GeoHashPair] = []
        joinedQueries = queries
        var didJoin: Bool = false
        repeat {
            var query1: GeoHashPair? = nil
            var query2: GeoHashPair? = nil
            
            for query in joinedQueries {
                for other in joinedQueries {
                    if (query != other) && (canJoinWith(query1: query, query2: other)) {
                        query1 = query
                        query2 = other
                    }
                }
            }
            if (query1 != nil) && (query2 != nil) {
                if let index1 = joinedQueries.firstIndex(of: query1!) {
                    joinedQueries.remove(at: index1)
                }
                if let index2 = joinedQueries.firstIndex(of: query2!){
                    joinedQueries.remove(at: index2)
                }
                if let newElement = joinWith(query1: query1!, query2: query2!) {
                    joinedQueries.append(newElement)
                }
                didJoin = true
            } else {
                didJoin = false
            }
        } while(didJoin)
        
        return joinedQueries
    }
    
    private func joinWith(query1: GeoHashPair, query2: GeoHashPair)->GeoHashPair?{
        if isPrefixTo(query1: query1, query2: query2){
            return initWithStartValue(startValue: query1.startValue, endValue: query2.endValue)
        } else if isPrefixTo(query1: query2, query2: query1) {
            return initWithStartValue(startValue: query2.startValue, endValue: query1.endValue)
        } else if isSuperQueryOf(query1: query1, query2: query2) {
            return query1
        } else if isSuperQueryOf(query1: query2, query2: query1) {
            return query2
        } else {
            return nil
        }
    }
    
    private func canJoinWith(query1: GeoHashPair, query2: GeoHashPair)->Bool {
        return ((isPrefixTo(query1: query1, query2: query2)) || (isPrefixTo(query1: query2, query2: query1)) || (isSuperQueryOf(query1: query1, query2: query2)) || (isSuperQueryOf(query1: query2, query2: query1)))
    }
    
    private func isSuperQueryOf(query1: GeoHashPair, query2: GeoHashPair)->Bool{
        if (query1.startValue == query2.startValue) || (query1.startValue < query2.startValue) {
            return ((query1.endValue == query2.endValue) || (query1.endValue > query2.endValue))
        } else {
            return false
        }
    }
    
    private func isPrefixTo(query1: GeoHashPair, query2: GeoHashPair)-> Bool {
        return ((query1.endValue >= query2.startValue) && (query1.startValue < query2.startValue) && (query1.endValue < query2.endValue))
    }
    
    private func wrapLongitude(longitude: CLLocationDegrees) -> CLLocationDegrees {
        if (longitude >= -180) && (longitude <= 180) {
            return longitude
        }
        let adjusted: Double = longitude + 180
        if (adjusted > 0) {
            return fmod(adjusted, 360)-180
        } else {
            return 180 - fmod(-adjusted, 360)
        }
    }
    
    private func addQuery(lat: CLLocationDegrees, lon: CLLocationDegrees, precision: UInt, bits: UInt)->GeoHashPair{
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let geoHash = newWithLocation(coordinate: coordinate, precision: precision)
        return geoHashQueryWithGeoHash(geoHash: geoHash, bits: bits)
        
    }
    
    private func newWithLocation(coordinate: CLLocationCoordinate2D, precision: UInt)->String{
        return initWithLocation(coordinate: coordinate, precision: precision)
    }
    
    private func initWithLocation(coordinate: CLLocationCoordinate2D, precision: UInt)->GFGeoHash{
        var hash = ""
        var latitudeRange = (lower: -90.0, upper: 90.0)
        var longitudeRange = (lower: -180.0, upper: 180.0)
        
        var bit = 0b10000 // 2^5 = 32
        var index = 0
        var even = true
        
        while hash.count < precision {
            if even {
                let average = (longitudeRange.0 + longitudeRange.1) / 2
                if coordinate.longitude >= average {
                    longitudeRange.lower = average
                    index |= bit
                } else {
                    longitudeRange.upper = average
                }
            } else {
                let average = (latitudeRange.0 + latitudeRange.1) / 2
                if coordinate.latitude >= average {
                    latitudeRange.lower = average
                    index |= bit
                } else {
                    latitudeRange.upper = average
                }
            }
            
            bit >>= 1
            even.toggle()
            
            if bit == 0b00000 {
                hash.append(GeoHashUtils.values[index])
                bit = 0b10000
                index = 0
            }
        }
        
        return hash
    }
    
    private func geoHashQueryWithGeoHash(geoHash: GFGeoHash, bits: UInt)->GeoHashPair{
        var hash: String = geoHash
        let precision: UInt = ((bits-1)/BITS_PER_GEOHASH_CHAR)+1
        if hash.count < precision {
            return newWithStartValue(startValue: hash, endValue: String(format: "%@~", hash))
        }
        hash = (hash as NSString).substring(to: Int(precision))
        let base = (hash as NSString).substring(to: hash.count-1)
        let lastCharacter = hash[hash.index(hash.startIndex, offsetBy: hash.count-1)]
        let lastValue: UInt = UInt(base32CharacterToValue(value: lastCharacter))
        let significantBits = bits - UInt(UInt(base.count)*BITS_PER_BASE32_CHAR)
        let unusedBits = (BITS_PER_BASE32_CHAR - significantBits)
        let startValue = (lastValue >> unusedBits) << unusedBits
        let endValue = startValue + (1 << unusedBits)
        let startHash: GFGeoHash = base + valueToBase32Character(value: Int(startValue))
        var endHash: GFGeoHash
        if endValue > 31 {
            endHash = base + "~"
        } else {
            endHash = base + valueToBase32Character(value: Int(endValue))
        }
        return GeoHashPair(startValue: startHash, endValue: endHash)
    }
    
    private func valueToBase32Character(value: Int) -> String {
        if value > 31 {
            return String("")
        } else {
            return String(GeoHashUtils.values[value])
        }
    }
    
    private func base32CharacterToValue(value: Character)->Int{
        let index = GeoHashUtils.values.firstIndex(of: value)
        return index ?? -1
    }
    
    private func newWithStartValue(startValue: GFGeoHash, endValue: GFGeoHash)->GeoHashPair{
        return initWithStartValue(startValue: startValue, endValue: endValue)
    }
    
    private func initWithStartValue(startValue: GFGeoHash, endValue: GFGeoHash)->GeoHashPair{
        return GeoHashPair(startValue: startValue, endValue: endValue)
    }
    
    private func bitsForRegion(region: MKCoordinateRegion) -> UInt{
        let BITS_PER_GEOHASH_CHAR: UInt = 5

        // The maximum number of bits in a geohash
        let MAXIMUM_BITS_PRECISION: UInt = (UInt(22)*(BITS_PER_GEOHASH_CHAR))
        let bitsLatitude: UInt = max(0, UInt(floor(log2(180/(region.span.latitudeDelta/2)))))*2
        let bitsLongitude: UInt = max(1, UInt(floor(log2(360/(region.span.longitudeDelta/2)))))*2-1;
        return min(bitsLatitude, min(bitsLongitude, MAXIMUM_BITS_PRECISION));
    }
    
    private func toLongitudeDegreesAtLatitude(distance: Double, latitude: CLLocationDegrees) -> CLLocationDegrees{
        let EPSILON = Double(1e-12)
        let radians = ((latitude)*Double.pi/180)
        let numerator = cos(radians)*EARTH_EQ_RADIUS*Double.pi/180
        let denominator = 1/sqrt(1-E2*sin(radians)*sin(radians))
        let deltaDegrees = numerator*denominator
        if deltaDegrees < EPSILON {
            return distance > 0 ? 360 : 0
        } else {
            return fmin(360, distance/deltaDegrees)
        }
    }
}
