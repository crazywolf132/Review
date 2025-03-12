//
//  ReviewApp.swift
//  Review
//
//  Created by Brayden Moon on 28/2/2025.
//

import SwiftUI

@main
struct ReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}
