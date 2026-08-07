import StoreKit
import SwiftUI

struct EcoCreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SupportPage(title: "Credits") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eco")
                        .font(.largeTitle.bold())
                    Text("Native OpenGOAL Runtime for Apple Platforms")
                        .font(.headline)
                        .foregroundStyle(DarkEcoTheme.accentGlow)
                }

                Text("Eco is an app by Zach Schwendiman, published by Zephyr Studios. Zach created the native Apple mobile port and its platform-runtime integration.")
                Text("Made available free as a gift to fans of the Jak trilogy.")

                Divider()

                Text("Eco is built on the open-source OpenGOAL project and the work of its contributors.")
                Link(destination: URL(string: "https://github.com/open-goal/jak-project")!) {
                    Label("Want to support the OpenGOAL project directly? Visit their official project page.",
                          systemImage: "arrow.up.right.square")
                }

                Text("Eco is an unofficial community project and is not affiliated with Sony Interactive Entertainment, Naughty Dog, or the OpenGOAL team.")
                    .foregroundStyle(.secondary)
                Text("Game data is not included. Players provide compatible data from copies they legally own.")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct EcoSupportView: View {
    @Environment(\.dismiss) private var dismiss
    let tipStore: EcoTipStore

    var body: some View {
        SupportPage(title: "Support") {
            VStack(spacing: 12) {
                NavigationLink {
                    EcoContactView()
                } label: {
                    SupportRow(title: "Contact", systemImage: "envelope")
                }

                NavigationLink {
                    EcoAboutView()
                } label: {
                    SupportRow(title: "About", systemImage: "info.circle")
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

private struct EcoAboutView: View {
    var body: some View {
        SupportPage(title: "About") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Eco is a free native Apple mobile port built by Zach Schwendiman and published by Zephyr Studios.")
                Text("It integrates the open-source OpenGOAL runtime with Apple platform rendering, input, audio, storage, and app lifecycle systems.")
                Text("Eco includes no game data. It is made as an unofficial gift to fans of the Jak trilogy.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EcoContactView: View {
    private let emailURL = URL(string: "mailto:contact@zephyrstudios.dev?subject=Eco%20Support")!

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
                Text("Optional one-time tips")
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

                Text("The app is free. These are optional one-time tips that help fund development and maintenance. Thank you for your support.")
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
