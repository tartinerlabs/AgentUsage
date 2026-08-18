//
//  BlogUsageSyncCard.swift
//  AgentUsage
//

#if os(macOS)
import SwiftUI

struct BlogUsageSyncCard: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var blogSyncTokenDraft = ""

    var body: some View {
        @Bindable var viewModel = viewModel

        settingsCard(title: "Blog Usage Sync", systemImage: "arrow.triangle.2.circlepath") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Sync")
                            .font(.body)
                        Text("Passively sync daily Claude, Codex, Cursor, OpenCode, and Grok usage to the blog backend")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.blogUsageSyncEnabled)
                        .labelsHidden()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Endpoint URL")
                        .font(.body)
                    TextField("Endpoint URL", text: $viewModel.blogUsageSyncEndpointURLString)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Blog Account")
                                .font(.body)
                            if viewModel.isBlogSignedIn {
                                Text(viewModel.blogOAuthAccountEmail ?? "Signed in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Sign in to authenticate sync with OAuth")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if viewModel.isBlogSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if viewModel.isBlogSignedIn {
                            Button("Sign Out") {
                                Task { await viewModel.signOutOfBlog() }
                            }
                            .disabled(viewModel.isBlogSigningIn)
                        } else {
                            Button("Sign in to blog") {
                                Task { await viewModel.signInToBlog() }
                            }
                            .disabled(viewModel.isBlogSigningIn)
                        }
                    }
                    if let blogOAuthError = viewModel.blogOAuthError {
                        Text(blogOAuthError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Fallback token (used when not signed in)")
                        .font(.body)
                    HStack {
                        SecureField("BLOG_MCP_AUTH_TOKEN", text: $blogSyncTokenDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await viewModel.saveBlogUsageSyncToken(blogSyncTokenDraft) }
                            }
                        Button("Save") {
                            Task { await viewModel.saveBlogUsageSyncToken(blogSyncTokenDraft) }
                        }
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Sync")
                            .font(.body)
                        Text(blogUsageSyncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.isBlogUsageSyncing || viewModel.blogUsageSyncStatus.state == .syncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Sync Now") {
                        Task { await viewModel.syncBlogUsageNow() }
                    }
                    .disabled(viewModel.isBlogUsageSyncing)
                }
            }
        }
        .task {
            await viewModel.loadBlogUsageSyncSettings()
            blogSyncTokenDraft = viewModel.blogUsageSyncToken
        }
    }

    private var blogUsageSyncStatusText: String {
        let status = viewModel.blogUsageSyncStatus
        var parts = [status.message]
        if let lastAttemptAt = status.lastAttemptAt {
            parts.append("Last attempt \(lastAttemptAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let lastSuccessAt = status.lastSuccessAt {
            parts.append("Last success \(lastSuccessAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " • ")
    }
}
#endif
