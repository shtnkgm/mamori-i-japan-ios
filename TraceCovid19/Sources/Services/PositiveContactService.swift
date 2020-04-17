//
//  PositiveContactService.swift
//  TraceCovid19
//
//  Created by yosawa on 2020/04/15.
//

import Foundation
import FirebaseStorage

final class PositiveContactService {
    private let storage: Storage
    private let jsonDecoder: JSONDecoder
    private let tempIdService: TempIdService
    private let deepContactCheck: DeepContactCheckService

    private var lastGeneration: Int64?
    private(set) var positiveContacts: [PositiveContact] = []

    private var fileName: String {
        return "positive_person_list.json"
    }

    init(
        storage: Storage,
        jsonDecoder: JSONDecoder,
        tempIdService: TempIdService,
        deepContactCheck: DeepContactCheckService
    ) {
        self.storage = storage
        self.jsonDecoder = jsonDecoder
        self.tempIdService = tempIdService
        self.deepContactCheck = deepContactCheck
    }

    enum PositiveContactStatus: Error {
        case error(Error?)
        case noNeedToLoad
    }

    /// 自身の陽性判定
    func isPositiveMyself() -> Bool {
        let myTempIDs = tempIdService.tempIDs.compactMap { $0.tempId }
        let positiveUUIDs = positiveContacts.compactMap { $0.uuid }
        for tempID in myTempIDs {
            if positiveUUIDs.contains(tempID) {
                return true
            }
        }
        return false
    }

    /// 陽性者と接触したか
    func isContactedPositivePeople() -> Bool {
        let deepContactUUIDs = deepContactCheck.getDeepContactUsers().compactMap { $0.tempId }
        let positiveContactUUIDs = positiveContacts.compactMap { $0.uuid }
        for uuid in deepContactUUIDs where positiveContactUUIDs.contains(uuid) {
            return true
        }
        return false
    }

    func load(completion: @escaping (Result<[PositiveContact], PositiveContactStatus>) -> Void) {
        let reference = storage.reference().child(fileName)

        reference.getMetadata { [weak self] metaData, error in
            guard let metaData = metaData, error == nil else {
                print("[PositiveContactService] error occurred: \(String(describing: error))")
                completion(.failure(.error(error)))
                return
            }

            print("[PositiveContactService] new generation: \(String(describing: metaData.generation)), last generation: \(String(describing: self?.lastGeneration))")
            if let lastGeneration = self?.lastGeneration,
                lastGeneration <= metaData.generation {
                // 取得不要
                completion(.failure(.noNeedToLoad))
                return
            }

            // メモリ指定（最大1MB）
            reference.getData(maxSize: 1 * 1024 * 1024) { [weak self] data, error in
                guard let sSelf = self else { return }
                guard let data = data, error == nil else {
                    print("[PositiveContactService] error occurred: \(String(describing: error))")
                    completion(.failure(.error(error)))
                    return
                }
                print("[PositiveContactService] data: \(String(describing: String(data: data, encoding: .utf8)))")

                do {
                    let list = try sSelf.jsonDecoder.decode(PositiveContactList.self, from: data)
                    self?.lastGeneration = metaData.generation
                    self?.positiveContacts = list.data
                    completion(.success(list.data))
                } catch {
                    print("[PositiveContactService] parse error: \(error)")
                    completion(.failure(.error(error)))
                }
            }
        }
    }
}

#if DEBUG
extension PositiveContactService {
    /// (デバッグ用) UUIDを陽性者リストに追加する
    func appendPositiveContact(uuid: String) {
        if !(positiveContacts.compactMap { $0.uuid }).contains(uuid) {
            positiveContacts.append(PositiveContact(uuid: uuid))
        }
    }

    func resetGeneration() {
        lastGeneration = nil
    }
}
#endif