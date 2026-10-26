//
//  Shelf+View.swift
//  Adverb
//

import AdverbCore
import AdverbRuntime
import SwiftUI

extension Shelf {
    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Kicker(text: "Adverb")
                Spacer()
                Button { selection.sheet = .newProject } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Color.adverbInkDim).help("New project")
            }
            .padding(.horizontal, .layer4)
            .padding(.top, .layer6)
            .padding(.bottom, .layer3)
            ScrollView {
                VStack(alignment: .leading, spacing: .layer4) {
                    ForEach(projects.state.projects) { project in
                        ProjectSection(project: project, campaigns: campaigns.state.campaigns(project.slug),
                                       busy: { generation.state.isBusy($0) }, selection: selection)
                    }
                }
                .padding(.horizontal, .layer3)
                .padding(.bottom, .layer4)
            }
        }
        .onReceive(changed) { _ in tick &+= 1 }
    }
}
