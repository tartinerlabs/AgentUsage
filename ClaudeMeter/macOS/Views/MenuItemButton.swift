//
//  MenuItemButton.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI

/// A button styled like a native macOS menu item with keyboard shortcut display
struct MenuItemButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 4) {
        MenuItemButton(title: "Open ClaudeMeter", shortcut: "⌘O") {}
        MenuItemButton(title: "Settings", shortcut: "⌘,") {}
        Divider()
        MenuItemButton(title: "Quit", shortcut: "⌘Q") {}
    }
    .padding()
    .frame(width: 250)
}
#endif
