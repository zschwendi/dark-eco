import StoreKit
import SwiftUI

struct EcoAboutView: View {
    @Environment(\.dismiss) private var dismiss
    let tipStore: EcoTipStore

    var body: some View {
        SupportPage(title: "About") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Dark Eco")
                        .font(.largeTitle.bold())

                    Text("This app is an unofficial iOS port for OpenGOAL developed by [Zach Schwendiman](https://x.com/zschwendi).")

                    Text("Dark Eco was built on the shoulders of the open-source OpenGOAL project and the work of its contributors.")

                    Link(destination: openGOALProjectURL) {
                        Label("Visit OpenGOAL project", systemImage: "arrow.up.right.square")
                    }

                    Link(destination: zephyrTermsURL) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }

                    Link(destination: zephyrPrivacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

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
                    EcoSupportDevelopmentView(tipStore: tipStore)
                } label: {
                    SupportRow(title: "Support Dark Eco", systemImage: "heart")
                }

                EcoLegalLinks()
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

private let openGOALProjectURL = URL(string: "https://github.com/open-goal/jak-project")!
private let zephyrTermsURL = URL(string: "https://zephyrstudios.dev/terms-of-use.html")!
private let zephyrPrivacyURL = URL(string: "https://zephyrstudios.dev/privacy-policy.html")!

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

private struct EcoSupportDevelopmentView: View {
    let tipStore: EcoTipStore

    var body: some View {
        SupportPage(title: "Support Dark Eco") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Optional Support")
                    .font(.title2.bold())

                Text("You can make an optional one-time purchase to support continued development.")
                    .foregroundStyle(.secondary)

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
                        .background(DarkEcoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(DarkEcoTheme.accent.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(tipStore.product(for: tip) == nil
                              || tipStore.purchasingProductID != nil
                              || tipStore.isRestoringPurchases)
                }

                Text("These optional purchases do not unlock features at this time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link(destination: openGOALProjectURL) {
                    Label("Support OpenGOAL directly on its official project page",
                          systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(DarkEcoTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(DarkEcoTheme.accent.opacity(0.5), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

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

                Button("Restore Purchases") {
                    Task { await tipStore.restorePurchases() }
                }
                .buttonStyle(.bordered)
                .disabled(tipStore.purchasingProductID != nil
                          || tipStore.isRestoringPurchases)

                EcoLegalLinks()
            }
        }
        .task { await tipStore.prepare() }
        .sheet(isPresented: Binding(
            get: { tipStore.isShowingThankYou },
            set: { if !$0 { tipStore.dismissThankYou() } }
        )) {
            EcoSupportThankYouView {
                tipStore.dismissThankYou()
            }
            .preferredColorScheme(.dark)
            .tint(DarkEcoTheme.accent)
        }
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

private struct EcoLegalLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            Link(destination: zephyrPrivacyURL) {
                Text("Privacy Policy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .underline()
            }

            Link(destination: zephyrTermsURL) {
                Text("Terms and Conditions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .underline()
            }
        }
    }
}

private struct EcoSupportThankYouView: View {
    let done: () -> Void

    var body: some View {
        NavigationStack {
            SupportPage(title: "Thank You") {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(DarkEcoTheme.accent)
                        .accessibilityHidden(true)
                    Text("Thank You!")
                        .font(.largeTitle.bold())
                    Text("Your support helps Zach continue developing and maintaining Dark Eco, and is sincerely appreciated.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { done() }
                }
            }
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
