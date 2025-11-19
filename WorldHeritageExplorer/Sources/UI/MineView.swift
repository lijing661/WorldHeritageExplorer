//  MineView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/9/25.
//

import SwiftUI

struct MineView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text("Mine")
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview { MineView() }
