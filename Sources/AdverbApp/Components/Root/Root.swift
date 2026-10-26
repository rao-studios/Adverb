//
//  Root.swift
//  Adverb
//
//  WHAT: The main window's content: whatever stands at the gate (the key, the working directory,
//        the drive, a first project), then the workbench. And the window's sheets.
//  IN:   ConfigService (the gate), DeskSelection
//  OUT:  Onboarding, DriveGate, Workbench, the sheets
//

import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct Root: GraniteComponent {
    @Command var center: Center
    @Relay var config: ConfigService
    let selection: DeskSelection
    @State var tick = 0

    init(selection: DeskSelection) { self.selection = selection }

    var configChanged: ObservableObjectPublisher { _config.relay.objectWillChange }
}
