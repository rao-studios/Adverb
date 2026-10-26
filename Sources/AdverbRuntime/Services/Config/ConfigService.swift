//
//  ConfigService.swift
//  AdverbRuntime
//
//  WHAT: The person's settings and the gate in front of the app, as Granite state: the key's
//        presence (never the key), the working directory and whether its drive is there, the model,
//        the renderer, the toolchain check.
//  OUT:  ConfigService+Center, Reducers/ConfigService.Set, Ops/ConfigOps
//  PIN:  A mirror: settings.json and the Keychain stay the truth; a change is written there by the
//        root and read back here (Craft's ConfigService).
//

import Foundation
import Granite

public struct ConfigService: GraniteService {
    @Service(.online) public var center: Center
    public init() {}
}

extension ConfigService {
    public func set(_ kind: Set.Meta.Kind) {
        let meta = Set.Meta(kind: kind)
        guard !Thread.isMainThread else { center.set.send(meta); return }
        let service = self
        DispatchQueue.main.async { service.center.set.send(meta) }
    }
}
