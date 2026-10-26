//
//  CampaignOps.swift
//  AdverbRuntime
//

import AdverbCore
import Foundation

public enum CampaignOps {
    public static func apply(_ kind: CampaignService.Set.Meta.Kind, to state: inout CampaignService.Center.State) {
        switch kind {
        case .loaded(let slug, let campaigns):
            state.byProject[slug] = campaigns.sorted { $0.createdAt > $1.createdAt }
        case .updated(let slug, let campaign):
            var list = state.byProject[slug] ?? []
            if let i = list.firstIndex(where: { $0.id == campaign.id }) { list[i] = campaign } else { list.insert(campaign, at: 0) }
            state.byProject[slug] = list.sorted { $0.createdAt > $1.createdAt }
        case .removed(let slug, let id):
            state.byProject[slug]?.removeAll { $0.id == id }
        case .forgetProject(let slug):
            state.byProject.removeValue(forKey: slug)
        }
    }
}
