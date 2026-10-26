//
//  Workbench.swift
//  Adverb
//
//  WHAT: The ready window: projects and their campaigns on the left, what is selected on the right.
//

import SwiftUI

struct Workbench: View {
    let selection: DeskSelection

    var body: some View {
        NavigationSplitView {
            Shelf(selection: selection)
                .navigationSplitViewColumnWidth(min: AdverbLayout.sidebar.min, ideal: AdverbLayout.sidebar.ideal, max: AdverbLayout.sidebar.max)
                .adverbSidebarRoot()
        } detail: {
            Desk(selection: selection)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
