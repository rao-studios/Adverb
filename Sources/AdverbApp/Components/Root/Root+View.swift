//
//  Root+View.swift
//  Adverb
//

import AdverbRuntime
import SwiftUI

extension Root {
    var view: some View {
        @Bindable var selection = selection
        let gate = config.state.gate
        return ZStack {
            Color.adverbPage.ignoresSafeArea()
            switch gate {
            case .loading:
                ProgressView().controlSize(.small)
            case .needsKey, .needsWorkdir, .noProjects:
                Onboarding(selection: selection)
            case .driveNotMounted(let volume):
                DriveGate(title: "\(volume) is not *plugged in.*",
                          message: "Adverb keeps its projects on \(volume). Plug it in and Adverb picks up where it left off. Nothing is written anywhere else meanwhile.")
            case .workdirMissing(let path):
                DriveGate(title: "The working directory *is gone.*",
                          message: "\(path) is not there any more. Choose it again, or another one.")
            case .ready:
                Workbench(selection: selection)
            }
        }
        .onReceive(configChanged) { _ in tick &+= 1 }
        .sheet(item: $selection.sheet) { sheet in
            Group {
                switch sheet {
                case .newProject: NewProjectSheet(selection: selection)
                case .manageProject(let slug): ManageProjectSheet(slug: slug, selection: selection)
                case .newCampaign(let slug): NewCampaignSheet(slug: slug, selection: selection)
                case .music(let slug, let campaign, let day): SongPicker(slug: slug, campaignID: campaign, dayIndex: day, selection: selection)
                }
            }
            .adverbRoot()
        }
    }
}
