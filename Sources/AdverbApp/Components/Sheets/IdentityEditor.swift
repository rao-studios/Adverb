//
//  IdentityEditor.swift
//  Adverb
//
//  WHAT: An app's identity, as the assets use it: the kicker they open with, the end card they close
//        on, the sites Claude may read. Presets for Rao's apps; every field editable.
//

import AdverbCore
import SwiftUI

struct IdentityEditor: View {
    @Binding var identity: AppIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: .layer3) {
            FormRow(label: "Starts from") {
                Picker("", selection: Binding(get: { AppIdentity.presets.first { $0 == identity }?.name ?? "custom" },
                                              set: { name in if let p = AppIdentity.presets.first(where: { $0.name == name }) { identity = p } })) {
                    ForEach(AppIdentity.presets, id: \.name) { Text($0.name).tag($0.name) }
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            HStack(spacing: .layer2) {
                FormRow(label: "App name") { AdverbTextField(placeholder: "Ambient", text: $identity.name) }
                FormRow(label: "Kicker") { AdverbTextField(placeholder: "Ambient, explained", text: $identity.kicker) }
            }
            HStack(spacing: .layer2) {
                FormRow(label: "Site") { AdverbTextField(placeholder: "https://…", text: Binding(get: { identity.siteURL ?? "" }, set: { identity.siteURL = $0.isEmpty ? nil : $0 })) }
                FormRow(label: "Repository") { AdverbTextField(placeholder: "https://github.com/…", text: Binding(get: { identity.repoURL ?? "" }, set: { identity.repoURL = $0.isEmpty ? nil : $0 })) }
            }
            FormRow(label: "End card", hint: "The title, the address and the tagline every asset closes on, under the Rao seal.") {
                HStack(spacing: .layer2) {
                    AdverbTextField(placeholder: "Ambient", text: $identity.endTitle)
                    AdverbTextField(placeholder: "ambient.rao.nyc", text: $identity.endSub)
                }
                AdverbTextField(placeholder: "Personal · private · cited · on your Mac", text: $identity.endSub2)
            }
            Toggle("Coming soon (assets say so and never describe it as shipping)", isOn: $identity.comingSoon).adverbType(.label)
        }
    }
}
