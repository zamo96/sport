import Foundation
import CoreLocation
import MapKit

@main
struct PlayerMapTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }

    static func area(_ id: String, cityID: String = "city-a", cityName: String = "Same city name", latitude: Double = 59.9, kind: String = "district") -> DiscoverMapArea {
        DiscoverMapArea(id: id, cityId: cityID, cityName: cityName, kind: kind,
                        districtId: kind == "district" ? id : nil, label: "Same district name", latitude: latitude, longitude: 30.3)
    }

    static func user(_ id: String, areas: [DiscoverMapArea], consent: Bool? = true, sports: [String] = ["tennis"]) throws -> DiscoverUser {
        var payload: [String: Any] = ["id": id, "name": id, "preferredSports": sports,
                                     "city": "Legacy city", "district": "Legacy district",
                                     "mapAreas": try JSONSerialization.jsonObject(with: JSONEncoder().encode(areas))]
        if let consent { payload["showOnMap"] = consent }
        return try JSONDecoder().decode(DiscoverUser.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static func item(_ membership: SimilarPlayersMapMembership) -> DiscoverPlayerMapItem {
        DiscoverPlayerMapItem(id: membership.id, userID: membership.user.id, areaID: membership.area.mapID,
                              anchorCoordinate: CLLocationCoordinate2D(latitude: membership.area.latitude, longitude: membership.area.longitude),
                              coordinate: CLLocationCoordinate2D(latitude: membership.area.latitude, longitude: membership.area.longitude),
                              areaLabel: membership.area.label, displayName: membership.user.name ?? "",
                              avatarPath: nil, sports: membership.user.preferredSports, sportLevels: membership.user.sportLevels)
    }

    static func main() throws {
        let a = area("central")
        let b = area("north", latitude: 60.1)
        let sameLabelOtherCity = area("central", cityID: "city-b")
        let elena = try user("elena", areas: [a])
        let maria = try user("maria", areas: [a, b, a], sports: ["tennis", "padel"])
        let sofia = try user("sofia", areas: [sameLabelOtherCity])
        let users = [elena, maria, sofia]
        let memberships = SimilarPlayersMapData.memberships(for: users)
        expect(memberships.count == 4, "Each player gets one card in each unique server area")
        expect(memberships.map(\.user.id) == ["elena", "maria", "maria", "sofia"], "Memberships retain canonical player ranking")
        expect(Set(memberships.map(\.id)).count == 4, "Membership IDs are distinct across both users and areas")
        expect(memberships[1].id != memberships[2].id, "One player in two areas has distinct annotation IDs")
        expect(memberships[0].area.mapID != memberships[3].area.mapID, "Same names/area IDs in different cities never merge")
        expect(memberships[0].area.latitude == a.latitude && memberships[2].area.latitude == b.latitude, "Only exact server coordinates are used")
        expect(SimilarPlayersMapData.memberships(for: users + [maria]).map(\.id) == memberships.map(\.id), "Duplicate users and duplicate memberships are removed")
        expect(SimilarPlayersMapData.mapUsers(users, sport: nil).map(\.id) == ["elena", "maria", "sofia"], "Cards below the map count unique players")
        let padel = SimilarPlayersMapData.memberships(for: users, sport: .padel)
        expect(padel.count == 2 && padel.allSatisfy { $0.user.id == "maria" }, "Sport filtering precedes every area membership")
        expect(SimilarPlayersMapData.mapUsers(users, sport: .padel).map(\.id) == ["maria"], "Multisport player appears once below map")

        let optedOut = try user("off", areas: [a], consent: false)
        let missingConsent = try user("legacy", areas: [a], consent: nil)
        let noAreas = try user("unmapped", areas: [])
        let invalidArea = try user("invalid", areas: [area("outside", latitude: 91), area("unsupported", kind: "gps")])
        let missingPayload = try JSONDecoder().decode(DiscoverUser.self, from: Data(#"{"id":"old"}"#.utf8))
        expect(!missingPayload.showOnMap && missingPayload.mapAreas.isEmpty, "Old payload defaults safely off and empty")
        expect(!missingConsent.showOnMap && missingConsent.mapAreas.isEmpty, "Consent cannot be inferred from attached areas")
        expect(optedOut.mapAreas.isEmpty, "Explicit opt-out ignores public areas")
        let hidden = [optedOut, missingConsent, noAreas, invalidArea, missingPayload]
        expect(SimilarPlayersMapData.memberships(for: hidden).isEmpty, "No inferred home district/city or viewer fallback")
        expect(SimilarPlayersMapData.filteredUsers(hidden, sport: nil).count == 5, "Normal cards keep map-ineligible players")
        let unknownCity = try user("unknown", areas: [area("canonical-city", cityID: "server-only-city", kind: "city")])
        expect(SimilarPlayersMapData.memberships(for: [unknownCity]).count == 1, "Valid server city remains supported without a native city catalog")
        let partial = try user("partial", areas: [area("invalid", latitude: 91), b])
        expect(SimilarPlayersMapData.memberships(for: [partial]).map(\.area.id) == ["north"], "Invalid areas do not remove valid memberships")

        let items = memberships.map(item)
        expect(DiscoverPlayerMapSelection.userIDs(in: items, membershipIDs: [items[0].id]) == ["elena"], "Individual callback uses canonical user ID")
        expect(DiscoverPlayerMapSelection.userIDs(in: items, membershipIDs: ["stale"]).isEmpty, "Removed membership cannot open a card")
        expect(DiscoverPlayerMapSelection.userIDs(in: items.filter { $0.id != items[2].id }, membershipIDs: [items[2].id]).isEmpty, "Revoked area cannot fall back to another membership of the same person")
        expect(DiscoverPlayerMapSelection.userIDs(in: [], membershipIDs: items.map(\.id)).isEmpty, "Logout/empty refresh discards queued selection")

        let polygon = [(59.88, 30.28), (59.88, 30.36), (59.94, 30.36), (59.94, 30.28)].map {
            CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1)
        }
        let district = area("central", cityID: "spb", cityName: "Санкт-Петербург")
        let twelve = try (1...12).map { try user(String(format: "player-%02d", $0), areas: [district], sports: $0.isMultiple(of: 2) ? ["tennis", "padel"] : ["tennis"]) }
        let pool = SimilarPlayersMapData.memberships(for: twelve)
        let matchingPolygon = SimilarPlayersDistrictLayout.validatedPolygon(for: district, polygonCity: "Санкт-Петербург", coordinates: polygon)
        expect(matchingPolygon != nil, "Matching district city and public anchor can use the public polygon")
        let positions = SimilarPlayersDistrictLayout.positions(for: pool) { _ in matchingPolygon }
        func signature(_ values: [String: CLLocationCoordinate2D]) -> [String] {
            values.map { "\($0.key):\($0.value.latitude):\($0.value.longitude)" }.sorted()
        }
        func distinct(_ points: [CLLocationCoordinate2D]) -> Int {
            Set(points.map { "\($0.latitude):\($0.longitude)" }).count
        }
        expect(positions.count == 12 && distinct(Array(positions.values)) == 12, "Twelve people sharing one district get twelve distinct display slots")
        expect(positions.values.allSatisfy { SimilarPlayersDistrictLayout.contains($0, polygon: polygon) }, "Every polygon slot stays inside the outline")
        expect(signature(positions) == signature(SimilarPlayersDistrictLayout.positions(for: pool.reversed()) { _ in matchingPolygon }), "Ranking does not change layout")
        let filteredIDs = Set(SimilarPlayersMapData.memberships(for: twelve, sport: .padel).map(\.id))
        let filteredPositions = positions.filter { filteredIDs.contains($0.key) }
        expect(filteredPositions.count == 6 && filteredPositions.allSatisfy { positions[$0.key]?.latitude == $0.value.latitude && positions[$0.key]?.longitude == $0.value.longitude }, "Local sport filtering retains positions from the full pool")
        let renamedPayload = try JSONEncoder().encode(twelve[0])
        var metadata = try JSONSerialization.jsonObject(with: renamedPayload) as! [String: Any]
        metadata["name"] = "Updated name"
        metadata["sportLevels"] = ["tennis": 10]
        let renamed = try JSONDecoder().decode(DiscoverUser.self, from: JSONSerialization.data(withJSONObject: metadata))
        let updatedPool = SimilarPlayersMapData.memberships(for: [renamed] + Array(twelve.dropFirst()))
        expect(signature(positions) == signature(SimilarPlayersDistrictLayout.positions(for: updatedPool) { _ in matchingPolygon }), "Photo/name/level metadata cannot move schematic slots")
        expect(pool.allSatisfy { $0.area.latitude == district.latitude && $0.area.longitude == district.longitude }, "Layout never changes the server anchor")
        let firstMember = pool[0]
        let shown = DiscoverPlayerMapItem(id: firstMember.id, userID: firstMember.user.id, areaID: firstMember.area.mapID,
            anchorCoordinate: CLLocationCoordinate2D(latitude: district.latitude, longitude: district.longitude), coordinate: positions[firstMember.id]!,
            areaLabel: district.label, displayName: "Player", avatarPath: nil, sports: [.tennis], sportLevels: [:])
        expect(shown.anchorCoordinate.latitude == district.latitude && shown.anchorCoordinate.longitude == district.longitude, "DTO explicitly keeps the exact public anchor separate")
        expect(shown.coordinate.latitude != shown.anchorCoordinate.latitude || shown.coordinate.longitude != shown.anchorCoordinate.longitude, "Schematic display position is independently represented")
        expect(SimilarPlayersDistrictLayout.validatedPolygon(for: district, polygonCity: "Москва", coordinates: polygon) == nil, "A same-named district cannot borrow another city's shape")
        let conflictingCity = area("central", cityID: "moscow", cityName: "Санкт-Петербург")
        expect(SimilarPlayersDistrictLayout.validatedPolygon(for: conflictingCity, polygonCity: "Санкт-Петербург", coordinates: polygon) == nil, "Recognized conflicting city ID rejects a shape")
        let foreign = area("central", cityName: "Moscow Idaho")
        expect(SimilarPlayersDistrictLayout.validatedPolygon(for: foreign, polygonCity: "Москва", coordinates: polygon) == nil, "City matching never uses broad substrings")
        let distant = area("central", cityID: "spb", cityName: "Санкт-Петербург", latitude: 55)
        expect(SimilarPlayersDistrictLayout.validatedPolygon(for: distant, polygonCity: "Санкт-Петербург", coordinates: polygon) == nil, "An inconsistent public center rejects a local outline")
        let cityOnly = area("whole-city", cityID: "spb", cityName: "Санкт-Петербург", kind: "city")
        expect(SimilarPlayersDistrictLayout.validatedPolygon(for: cityOnly, polygonCity: "Санкт-Петербург", coordinates: polygon) == nil, "City-wide memberships cannot borrow district polygons")
        let fallback = SimilarPlayersDistrictLayout.positions(for: pool) { _ in nil }
        expect(fallback.count == 12 && distinct(Array(fallback.values)) == 12, "Unknown shapes get distinct public-center grid slots")
        expect(fallback.values.allSatisfy(CLLocationCoordinate2DIsValid), "Fallback coordinates remain valid")
        expect(fallback.values.allSatisfy { abs($0.latitude - district.latitude) < 0.02 && abs($0.longitude - district.longitude) < 0.04 }, "Fallback remains compact around the shared public center")
        let polar = SimilarPlayersDistrictLayout.fallbackSlots(count: 12, anchor: CLLocationCoordinate2D(latitude: 90, longitude: 180))
        expect(polar.allSatisfy(CLLocationCoordinate2DIsValid) && distinct(polar) == 12, "Dateline/polar fallback preserves valid distinct slots")
        let allAreas = (1...18).map { area("district-\($0)", latitude: 59.8 + Double($0) * 0.01) }
        let allCityUsers = try (1...12).map { try user("city-player-\($0)", areas: allAreas) }
        let allCityMemberships = SimilarPlayersMapData.memberships(for: allCityUsers)
        let allCityPositions = SimilarPlayersDistrictLayout.positions(for: allCityMemberships) { _ in nil }
        expect(allCityMemberships.count == 216 && Set(allCityMemberships.map(\.id)).count == 216 && allCityPositions.count == 216, "All-city preferred districts preserve every unique membership")
        expect(SimilarPlayersMapData.mapUsers(allCityUsers, sport: nil).count == 12, "Many district memberships still count each player once below the map")
        let changed = SimilarPlayersDistrictLayout.positions(for: Array(pool.dropFirst())) { _ in matchingPolygon }
        expect(changed.count == 11 && distinct(Array(changed.values)) == 11, "A changed server pool may reflow while preserving valid distinct slots")
        let concave = [(0.0, 0.0), (0, 4), (1, 4), (1, 1), (4, 1), (4, 0)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        expect(SimilarPlayersDistrictLayout.contains(CLLocationCoordinate2D(latitude: 0.5, longitude: 3), polygon: concave), "Containment handles concave district interiors")
        expect(!SimilarPlayersDistrictLayout.contains(CLLocationCoordinate2D(latitude: 3, longitude: 3), polygon: concave), "Concave cutouts are never treated as inside")
        let concaveArea = DiscoverMapArea(id: "concave", cityId: "spb", cityName: "Санкт-Петербург", kind: "district", districtId: "concave", label: "Concave", latitude: 3, longitude: 3)
        expect(SimilarPlayersDistrictLayout.validatedPolygon(for: concaveArea, polygonCity: "Санкт-Петербург", coordinates: concave) == nil, "An anchor inside the bounding box but outside a concave polygon rejects that shape")

        let nested: [DiscoverPlayerMapMembershipNode] = [.group([.member(items[2].id), .group([.member(items[0].id), .member(items[1].id), .member(items[2].id), .member("removed")])])]
        let resolvedMembers = DiscoverPlayerMapCluster.membershipIDs(in: items, nodes: nested)
        expect(resolvedMembers == Array(items.prefix(3)).map(\.id), "Nested native clusters flatten current memberships in canonical order")
        expect(DiscoverPlayerMapSelection.userIDs(in: items, membershipIDs: resolvedMembers) == ["elena", "maria"], "Numeric groups count distinct people, not repeated district memberships")
        let onePersonMembers = DiscoverPlayerMapCluster.membershipIDs(in: items, nodes: [.group([.member(items[1].id), .member(items[2].id)])])
        expect(DiscoverPlayerMapSelection.userIDs(in: items, membershipIDs: onePersonMembers).count == 1, "One person in two areas has group count one")
        expect(DiscoverPlayerMapCluster.membershipIDs(in: [], nodes: nested).isEmpty, "Old cluster membership is discarded after logout or revocation")
        expect(DiscoverPlayerMapCluster.membershipIDs(in: [items[0]], nodes: nested) == [items[0].id], "Visible badges resolve against refreshed eligibility")

        let displayCoordinates = Array(positions.values)
        let center = MKMapPoint(displayCoordinates[0])
        var viewport = MKMapRect(x: center.x - 80_000, y: center.y - 120_000, width: 160_000, height: 240_000)
        for step in 0..<8 {
            let next = DiscoverPlayerMapCluster.zoomRect(current: viewport, coordinates: displayCoordinates)!
            expect(next.width < viewport.width && next.height < viewport.height, "Repeated group tap \(step) makes zoom progress")
            expect(abs(next.width / next.height - viewport.width / viewport.height) < 0.000001, "Repeated group zoom keeps the viewport aspect ratio")
            expect(displayCoordinates.map(MKMapPoint.init).contains(where: { next.contains($0) }), "A group activation keeps an actual schematic member visible")
            viewport = next
        }
        let tight = MKMapRect(x: center.x, y: center.y, width: 500, height: 250)
        let tightened = DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: displayCoordinates)!
        expect(tightened.width == 250 && tightened.height == 125, "Tight clusters do not stall at the initial 800-meter fit or old padding")
        let minimum = MKMapRect(x: center.x, y: center.y, width: 20, height: 10)
        let atMinimum = DiscoverPlayerMapCluster.zoomRect(current: minimum, coordinates: displayCoordinates)!
        expect(atMinimum.width <= minimum.width && atMinimum.height <= minimum.height, "Finite floor never zooms out an already smaller viewport")
        expect(DiscoverPlayerMapCluster.zoomRect(current: .null, coordinates: displayCoordinates) == nil, "Null viewports cannot produce a zoom")
        expect(DiscoverPlayerMapCluster.zoomRect(current: MKMapRect(x: 0, y: 0, width: 0, height: 10), coordinates: displayCoordinates) == nil, "Empty viewports are ignored")
        expect(DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: []) == nil, "Stale empty groups cannot move the camera")
        expect(DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: [CLLocationCoordinate2D(latitude: .nan, longitude: 0)]) == nil, "Invalid display coordinates are ignored")
        let opposite = [MKMapPoint(x: center.x - 1000, y: center.y), MKMapPoint(x: center.x + 1000, y: center.y)].map(\.coordinate)
        let between = DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: opposite)!
        expect(opposite.map(MKMapPoint.init).contains(where: { between.contains($0) }), "When half-zoom excludes both sides, center an actual member rather than empty space")
        let onePersonZoom = DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: items[1...2].map(\.coordinate))!
        expect(onePersonZoom.width < tight.width, "A unique-player group remains a zoom action")
        let changedAnchors = items.map { item in
            DiscoverPlayerMapItem(id: item.id, userID: item.userID, areaID: item.areaID,
                anchorCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), coordinate: item.coordinate,
                areaLabel: item.areaLabel, displayName: item.displayName, avatarPath: item.avatarPath,
                sports: item.sports, sportLevels: item.sportLevels)
        }
        let normalZoom = DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: items.map(\.coordinate))!
        let anchorIndependentZoom = DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: changedAnchors.map(\.coordinate))!
        expect(normalZoom.origin.x == anchorIndependentZoom.origin.x && normalZoom.origin.y == anchorIndependentZoom.origin.y && normalZoom.width == anchorIndependentZoom.width && normalZoom.height == anchorIndependentZoom.height, "Cluster zoom uses schematic display coordinates, never public anchors or personal locations")
        let dateLine = [CLLocationCoordinate2D(latitude: 0, longitude: 179.99), CLLocationCoordinate2D(latitude: 0, longitude: -179.99)]
        let dateLineZoom = DiscoverPlayerMapCluster.zoomRect(current: tight, coordinates: dateLine)!
        expect(dateLineZoom.origin.x > MKMapRect.world.width * 0.9 || dateLineZoom.origin.x < MKMapRect.world.width * 0.1, "Dateline groups do not recenter on the opposite side of the world")
        print("PASS: \(assertions) player-map assertions")
    }
}
