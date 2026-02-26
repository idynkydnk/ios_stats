import Foundation
import CloudKit

/// Manages a shared database in CloudKit. Owner creates a share and gets a code;
/// others accept the share with that code. All participants read/write the same Game records.
final class CloudKitManager {
    static let shared = CloudKitManager()
    
    private let container: CKContainer
    private let privateDB: CKDatabase
    private let publicDB: CKDatabase
    
    private let defaults = UserDefaults.standard
    private let rootRecordNameKey = "stats_ck_root_record_name"
    private let rootZoneNameKey = "stats_ck_root_zone_name"
    private let rootOwnerNameKey = "stats_ck_root_owner_name"
    
    enum RecordType {
        static let database = "Database"
        static let game = "Game"
        static let shareLookup = "ShareLookup"
    }
    
    private init() {
        // Use iCloud container; enable "iCloud" + "CloudKit" in Signing & Capabilities and add container iCloud.com.kt.stats
        container = CKContainer(identifier: "iCloud.com.kt.stats")
        privateDB = container.privateCloudDatabase
        publicDB = container.publicCloudDatabase
    }
    
    // MARK: - Shared state
    
    /// True when this device has created or joined a shared database (root record ID is stored).
    var hasSharedDatabase: Bool {
        rootRecordID != nil
    }
    
    private var rootRecordID: CKRecord.ID? {
        get {
            guard let name = defaults.string(forKey: rootRecordNameKey),
                  let zoneName = defaults.string(forKey: rootZoneNameKey),
                  let ownerName = defaults.string(forKey: rootOwnerNameKey) else { return nil }
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
            return CKRecord.ID(recordName: name, zoneID: zoneID)
        }
        set {
            if let id = newValue {
                defaults.set(id.recordName, forKey: rootRecordNameKey)
                defaults.set(id.zoneID.zoneName, forKey: rootZoneNameKey)
                defaults.set(id.zoneID.ownerName, forKey: rootOwnerNameKey)
            } else {
                defaults.removeObject(forKey: rootRecordNameKey)
                defaults.removeObject(forKey: rootZoneNameKey)
                defaults.removeObject(forKey: rootOwnerNameKey)
            }
        }
    }
    
    /// Clear shared database state (e.g. when user leaves).
    func clearSharedDatabase() {
        rootRecordID = nil
    }
    
    // MARK: - Create shared database (owner)
    
    /// Creates a root record and share, saves code→URL in public DB, returns the 6-char code.
    func createSharedDatabase(completion: @escaping (Result<String, Error>) -> Void) {
        let rootRecord = CKRecord(recordType: RecordType.database)
        rootRecord["createdAt"] = Date()
        
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Beach Volleyball"
        share.publicPermission = .none
        
        let modifyOp = CKModifyRecordsOperation(recordsToSave: [rootRecord, share], recordIDsToDelete: nil)
        modifyOp.savePolicy = .changedKeys
        modifyOp.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success:
                guard let shareURL = share.url else {
                    completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Share has no URL"])))
                    return
                }
                let code = Self.generateCode()
                self?.saveShareLookup(code: code, shareURL: shareURL) { lookupResult in
                    switch lookupResult {
                    case .success:
                        self?.rootRecordID = rootRecord.recordID
                        completion(.success(code))
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
        privateDB.add(modifyOp)
    }
    
    private static func generateCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
    
    private func saveShareLookup(code: String, shareURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let zoneID = CKRecordZone.default().zoneID
        let record = CKRecord(recordType: RecordType.shareLookup, recordID: CKRecord.ID(recordName: code, zoneID: zoneID))
        record["code"] = code
        record["shareURL"] = shareURL.absoluteString
        
        publicDB.save(record) { _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Accept share (joiner)
    
    /// Fetches share URL by code, fetches share metadata, accepts share. On success, root record ID is stored.
    func acceptShare(code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count == 6 else {
            completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Code must be 6 characters"])))
            return
        }
        
        let zoneID = CKRecordZone.default().zoneID
        let recordID = CKRecord.ID(recordName: trimmed, zoneID: zoneID)
        publicDB.fetch(withRecordID: recordID) { [weak self] record, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let record = record,
                  let urlString = record["shareURL"] as? String,
                  let url = URL(string: urlString) else {
                completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid share code"])))
                return
            }
            
            let fetchMetaOp = CKFetchShareMetadataOperation(shareURLs: [url])
            fetchMetaOp.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let metadata):
                    self?.container.accept(metadata) { acceptedShare, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        if let rootRecord = metadata.rootRecord {
                            self?.rootRecordID = rootRecord.recordID
                            completion(.success(()))
                        } else {
                            completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid share metadata"])))
                        }
                    }
                case .failure(let err):
                    completion(.failure(err))
                }
            }
            self?.container.add(fetchMetaOp)
        }
    }
    
    // MARK: - Games (CRUD)
    
    func fetchAllGames(completion: @escaping (Result<[LegacyGame], Error>) -> Void) {
        guard let rootID = rootRecordID else {
            completion(.success([]))
            return
        }
        
        let ref = CKRecord.Reference(recordID: rootID, action: CKRecord.ReferenceAction.none)
        let pred = NSPredicate(format: "parentRef == %@", ref)
        let query = CKQuery(recordType: RecordType.game, predicate: pred)
        query.sortDescriptors = [NSSortDescriptor(key: "gameDate", ascending: false)]
        
        privateDB.perform(query, inZoneWith: rootID.zoneID) { [weak self] records, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            let games = (records ?? []).map { self.legacyGame(from: $0) }
            completion(.success(games))
        }
    }
    
    func insertGame(winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int,
                    completion: @escaping (Result<LegacyGame, Error>) -> Void) {
        guard rootRecordID != nil else {
            completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No shared database"])))
            return
        }
        
        fetchMaxGameNumber { [weak self] result in
            guard let self = self, let rootID = self.rootRecordID else { return }
            switch result {
            case .success(let maxNum):
                let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: rootID.zoneID)
                let record = CKRecord(recordType: RecordType.game, recordID: recordID)
                record["gameNumber"] = maxNum + 1
                record["winner1"] = Self.capitalize(winner1)
                record["winner2"] = Self.capitalize(winner2)
                record["winnerScore"] = winnerScore
                record["loser1"] = Self.capitalize(loser1)
                record["loser2"] = Self.capitalize(loser2)
                record["loserScore"] = loserScore
                record["gameDate"] = Date()
                record["parentRef"] = CKRecord.Reference(recordID: rootID, action: CKRecord.ReferenceAction.deleteSelf)
                
                self.privateDB.save(record) { saved, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    completion(.success(self.legacyGame(from: record)))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }
    
    func updateGame(recordName: String, winner1: String, winner2: String, winnerScore: Int,
                    loser1: String, loser2: String, loserScore: Int,
                    completion: @escaping (Result<Void, Error>) -> Void) {
        guard let zoneID = rootRecordID?.zoneID else {
            completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No shared database"])))
            return
        }
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        privateDB.fetch(withRecordID: recordID) { [weak self] record, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let record = record else {
                completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Record not found"])))
                return
            }
            record["winner1"] = Self.capitalize(winner1)
            record["winner2"] = Self.capitalize(winner2)
            record["winnerScore"] = winnerScore
            record["loser1"] = Self.capitalize(loser1)
            record["loser2"] = Self.capitalize(loser2)
            record["loserScore"] = loserScore
            
            self?.privateDB.save(record) { _, error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    func deleteGame(recordName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let zoneID = rootRecordID?.zoneID else {
            completion(.failure(NSError(domain: "CloudKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No shared database"])))
            return
        }
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        privateDB.delete(withRecordID: recordID) { _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    private func fetchMaxGameNumber(completion: @escaping (Result<Int, Error>) -> Void) {
        guard let rootID = rootRecordID else {
            completion(.success(0))
            return
        }
        let ref = CKRecord.Reference(recordID: rootID, action: CKRecord.ReferenceAction.none)
        let pred = NSPredicate(format: "parentRef == %@", ref)
        let query = CKQuery(recordType: RecordType.game, predicate: pred)
        
        privateDB.perform(query, inZoneWith: rootID.zoneID) { records, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let maxNum = (records ?? []).compactMap { $0["gameNumber"] as? Int }.max() ?? 0
            completion(.success(maxNum))
        }
    }
    
    private func legacyGame(from record: CKRecord) -> LegacyGame {
        let id = record["gameNumber"] as? Int ?? 0
        let date = record["gameDate"] as? Date ?? Date()
        let winner1 = record["winner1"] as? String ?? ""
        let winner2 = record["winner2"] as? String ?? ""
        let winnerScore = record["winnerScore"] as? Int ?? 21
        let loser1 = record["loser1"] as? String ?? ""
        let loser2 = record["loser2"] as? String ?? ""
        let loserScore = record["loserScore"] as? Int ?? 19
        let recordName = record.recordID.recordName
        return LegacyGame(id: id, date: date, winner1: winner1, winner2: winner2, winnerScore: winnerScore, loser1: loser1, loser2: loser2, loserScore: loserScore, recordName: recordName)
    }
    
    private static func capitalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { word in
                let w = String(word)
                guard let first = w.first else { return w }
                return first.uppercased() + w.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
