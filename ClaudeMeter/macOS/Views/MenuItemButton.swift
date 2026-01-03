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

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(isHovered ? .white : .primary)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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
