//
//  Exchange.swift
//  LLVS
//
//  Created by Drew McCormack on 25/02/2019.
//

import Foundation

enum ExchangeError: Swift.Error {
    case remoteVersionsWithUnknownPredecessors
}

public protocol ExchangeClient: class {
    func newVersionsAreAvailable(via exchange: Exchange)
}

public protocol Exchange {
    var client: ExchangeClient? { get set }
    var store: Store { get }
    
    func retrieve(executingUponCompletion completionHandler: @escaping CompletionHandler<[Version.Identifier]>)
    func retrieveAllVersionIdentifiers(executingUponCompletion completionHandler: @escaping CompletionHandler<[Version.Identifier]>)
    func retrieveVersions(identifiedBy versionIdentifiers: [Version.Identifier], executingUponCompletion completionHandler: @escaping CompletionHandler<[Version]>)
    func retrieveValueChanges(forVersionIdentifiedBy versionIdentifier: Version.Identifier, executingUponCompletion completionHandler: @escaping CompletionHandler<[Value.Change]>)

    func send(executingUponCompletion completionHandler: @escaping CompletionHandler<[Version.Identifier]>)
    func send(_ version: Version, with valueChanges: [Value.Change], executingUponCompletion completionHandler: @escaping CompletionHandler<Void>)
}

public extension Exchange {
    
    func retrieve(executingUponCompletion completionHandler: @escaping CompletionHandler<[Version.Identifier]>) {
        var remoteIds: [Version.Identifier]!
        let retrieveIds = AsynchronousTask { finish in
            self.retrieveAllVersionIdentifiers { result in
                remoteIds = result.value
                finish(result.taskResult)
            }
        }
        
        var remoteVersions: [Version]!
        let retrieveVersions = AsynchronousTask { finish in
            let toRetrieveIds = self.versionIdentifiersMissingFromHistory(forRemoteIdentifiers: remoteIds)
            self.retrieveVersions(identifiedBy: toRetrieveIds) { result in
                remoteVersions = result.value
                finish(result.taskResult)
            }
        }
        
        let addToHistory = AsynchronousTask { finish in
            self.addToHistory(remoteVersions) { result in
                finish(result.taskResult)
            }
        }
                    
        [retrieveIds, retrieveVersions, addToHistory].executeInOrder { result in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
            case .success:
                completionHandler(.success(remoteIds!))
            }
        }
    }
    
    private func versionIdentifiersMissingFromHistory(forRemoteIdentifiers remoteIdentifiers: [Version.Identifier]) -> [Version.Identifier] {
        var toRetrieveIds: [Version.Identifier]!
        self.store.queryHistory { history in
            let storeVersionIds = Set(history.allVersionIdentifiers)
            let remoteVersionIds = Set(remoteIdentifiers)
            toRetrieveIds = Array(remoteVersionIds.subtracting(storeVersionIds))
        }
        return toRetrieveIds
    }
    
    private func addToHistory(_ versions: [Version], executingUponCompletion completionHandler: @escaping CompletionHandler<Void>) {
        if versions.isEmpty {
            completionHandler(.success(()))
        } else if let version = appendableVersion(from: versions) {
            retrieveValueChanges(forVersionIdentifiedBy: version.identifier) { result in
                switch result {
                case let .failure(error):
                    completionHandler(.failure(error))
                case let .success(valueChanges):
                    do {
                        try self.store.addVersion(version, storing: valueChanges)
                    } catch {
                        completionHandler(.failure(error))
                        return
                    }
                    
                    var reducedVersions = versions
                    reducedVersions.removeAll(where: { $0.identifier == version.identifier })
                    self.addToHistory(reducedVersions, executingUponCompletion: completionHandler)
                }
            }
        } else {
            completionHandler(.failure(ExchangeError.remoteVersionsWithUnknownPredecessors))
        }
    }
    
    private func appendableVersion(from versions: [Version]) -> Version? {
        return versions.first { v in
            return store.history(includesVersionsIdentifiedBy: v.predecessors?.identifiers ?? [])
        }
    }
    
    func send(executingUponCompletion completionHandler: @escaping CompletionHandler<[Version.Identifier]>) {
        
    }
}
