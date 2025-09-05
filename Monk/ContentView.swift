//
//  ContentView.swift
//  Monk
//
//  Created by Gabriel Berezovsky on 25/8/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager: FocusManager?

    var body: some View {
        Group {
            if let manager = manager {
                HomeView()
                    .environmentObject(manager)
            } else {
                ProgressView().task {
                    await MainActor.run { self.manager = FocusManager(modelContext: modelContext) }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
