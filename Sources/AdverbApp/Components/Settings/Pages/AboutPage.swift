//
//  AboutPage.swift
//  Adverb
//

import AdverbCore
import SwiftUI

struct AboutPage: View {
    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                HStack(spacing: .layer3) {
                    AdverbMark(size: 52)
                    VStack(alignment: .leading, spacing: .hairline) {
                        Headline(text: "Adverb", role: .title)
                        Text("A month of motion, planned and beat-matched.").adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                    }
                }
                FieldRow(label: "Version", value: "\(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))")
                FieldRow(label: "Commit", value: info("AdverbBuildCommit"))
                FieldRow(label: "Built", value: info("AdverbBuildDate"))
                FieldRow(label: "Kit", value: "rao-motion-assets kit \(KitInstaller.bundledVersion)")
                Text("Rao Studios. Apache-2.0.").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        }
    }

    private func info(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—" }
}
