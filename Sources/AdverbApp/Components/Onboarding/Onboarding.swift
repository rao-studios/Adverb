//
//  Onboarding.swift
//  Adverb
//
//  WHAT: First launch, in three steps, each shown while it is what stands at the gate: the models
//        (downloaded once, then everything runs on this Mac), the working directory (the T9), the
//        first project.
//  IN:   ConfigService (gate, settings), ModelService (what is installed, what is downloading)
//  OUT:  AdverbRuntimeRoot (downloadRecommended, downloadModel, useTextModel, chooseWorkdir, createProject)
//

import AdverbCore
import AdverbRuntime
import Combine
import Granite
import SwiftUI

struct Onboarding: GraniteComponent {
    @Command var center: Center
    @Relay var config: ConfigService
    @Relay var models: ModelService
    let selection: DeskSelection
    @State var form = OnboardingForm()
    @State var tick = 0

    init(selection: DeskSelection) { self.selection = selection }

    var configChanged: ObservableObjectPublisher { _config.relay.objectWillChange }
    var modelsChanged: ObservableObjectPublisher { _models.relay.objectWillChange }

    enum Step: Int, CaseIterable { case models, workdir, project
        var title: String { ["The models", "Where Adverb works", "The first project"][rawValue] }
    }

    var step: Step {
        switch config.state.gate {
        case .needsModels: .models
        case .needsWorkdir: .workdir
        default: .project
        }
    }
}

/// What is typed in onboarding: in the form, never in a service (Craft's AccountForm PIN: a relay
/// re-renders 0.2 s after it settles, which a field cannot wait for).
@MainActor
@Observable
final class OnboardingForm {
    var projectName = ""
    var context: URL?
    var preset = AppIdentity.ambient.name
    var creating = false
}
