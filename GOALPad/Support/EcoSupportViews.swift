import StoreKit
import SwiftUI

struct EcoAboutView: View {
    @Environment(\.dismiss) private var dismiss
    let tipStore: EcoTipStore

    var body: some View {
        SupportPage(title: "About") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dark Eco")
                            .font(.largeTitle.bold())
                    }

                    Text("Dark Eco is a native Apple runtime for OpenGOAL developed by Zach Schwendiman, published by Zephyr Studios.")
          

                    Text("Dark Eco is built on the open-source OpenGOAL project and the work of its contributors.")


                    Text("Dark Eco is not affiliated with Sony Interactive Entertainment, Naughty Dog, or the OpenGOAL team.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                NavigationLink {
                    EcoContactView()
                } label: {
                    SupportRow(title: "Contact", systemImage: "envelope")
                }

                NavigationLink {
                    EcoDonateView(tipStore: tipStore)
                } label: {
                    SupportRow(title: "Donate", systemImage: "heart")
                }
            }
            .buttonStyle(.plain)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct EcoContactView: View {
    private let emailURL = URL(string: "mailto:contact@zephyrstudios.dev?subject=Dark%20Eco%20Support")!

    var body: some View {
        SupportPage(title: "Contact") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Questions, feedback, or a bug report?")
                Link(destination: emailURL) {
                    Label("Contact support", systemImage: "envelope")
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
                Text("contact@zephyrstudios.dev")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct EcoDonateView: View {
    let tipStore: EcoTipStore

    var body: some View {
        SupportPage(title: "Donate") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Optional tips")
                    .font(.title2.bold())

            ForEach(EcoTip.allCases) { tip in
                Button {
                    Task { await tipStore.purchase(tip) }
                } label: {
                        HStack(spacing: 12) {
                            Text(tip.emoji)
                            Text(tip.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            price(for: tip)
                        }
                        .frame(minHeight: 50)
                        .padding(.horizontal, 14)
                        .background(DarkEcoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(DarkEcoTheme.accent.opacity(0.5), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(tipStore.product(for: tip) == nil
                              || tipStore.purchasingProductID != nil)
            }

            Link(destination: URL(string: "https://github.com/open-goal/jak-project")!) {
                Label("Want to support the OpenGOAL project directly? Visit their official project page.",
                      systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(DarkEcoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(DarkEcoTheme.accent.opacity(0.5), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Text("The app is free. Tips are optional and unlock no features or content.")
                .font(.footnote)
                    .foregroundStyle(.secondary)

                if let notice = tipStore.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(DarkEcoTheme.accentGlow)
                }

                if !tipStore.isLoading && EcoTip.allCases.contains(where: {
                    tipStore.product(for: $0) == nil
                }) {
                    Button("Try Again") {
                        Task { await tipStore.reloadProducts() }
                    }
                }
            }
        }
        .task { await tipStore.prepare() }
    }

    @ViewBuilder
    private func price(for tip: EcoTip) -> some View {
        if tipStore.purchasingProductID == tip.rawValue {
            ProgressView()
        } else if let product = tipStore.product(for: tip) {
            Text(product.displayPrice)
                .font(.headline.monospacedDigit())
        } else if tipStore.isLoading {
            ProgressView()
        } else {
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SupportRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 14)
        .background(DarkEcoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

private struct SupportPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            DarkEcoPanel {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [Color.black, DarkEcoTheme.background],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .navigationTitle(title)
        .tint(DarkEcoTheme.accent)
    }
}
