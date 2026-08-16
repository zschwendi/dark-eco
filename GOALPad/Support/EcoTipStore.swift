import Observation
import StoreKit

nonisolated enum EcoTip: String, CaseIterable, Identifiable, Sendable {
    case coffee = "com.zephyrstudiosllc.eco.tip.coffee"
    case development = "com.zephyrstudiosllc.eco.tip.development"
    case topSupporter = "com.zephyrstudiosllc.eco.tip.topsupporter"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .coffee: "💜"
        case .development: "🚀"
        case .topSupporter: "✨"
        }
    }

    var title: String {
        switch self {
        case .coffee: "Small Support"
        case .development: "Development Support"
        case .topSupporter: "Extra Support"
        }
    }
}

nonisolated enum EcoTipTransactionObserver {
    static func run() async {
        for await result in Transaction.unfinished {
            await finishIfVerifiedEcoTip(result)
        }
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }
            await finishIfVerifiedEcoTip(result)
        }
    }

    private static func finishIfVerifiedEcoTip(
        _ result: VerificationResult<Transaction>
    ) async {
        guard case .verified(let transaction) = result,
              EcoTip(rawValue: transaction.productID) != nil else { return }
        await transaction.finish()
    }
}

@MainActor
@Observable
final class EcoTipStore {
    private(set) var products: [String: Product] = [:]
    private(set) var isLoading = false
    private(set) var purchasingProductID: String?
    private(set) var isRestoringPurchases = false
    private(set) var notice: String?
    private(set) var isShowingThankYou = false

    func prepare() async {
        guard !isLoading else { return }
        await reloadProducts()
    }

    func reloadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        notice = nil
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: EcoTip.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            if products.count != EcoTip.allCases.count {
                notice = "Some support options aren’t available from the App Store right now."
            }
        } catch {
            products = [:]
            notice = "Support options couldn’t be loaded. Check your connection and try again."
        }
    }

    func product(for tip: EcoTip) -> Product? {
        products[tip.rawValue]
    }

    func purchase(_ tip: EcoTip) async {
        #if os(visionOS)
        notice = "Support purchases aren’t available on visionOS."
        return
        #else
        guard purchasingProductID == nil else { return }
        guard let product = product(for: tip) else {
            notice = "That support option isn’t available from the App Store right now."
            return
        }

        purchasingProductID = product.id
        notice = nil
        defer { purchasingProductID = nil }

        do {
            switch try await product.purchase() {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    isShowingThankYou = true
                case .unverified:
                    notice = "The App Store couldn’t verify this purchase. Contact support if it appears in your purchase history."
                }
            case .pending:
                notice = "This purchase is pending App Store approval."
            case .userCancelled:
                notice = "Purchase canceled. You weren’t charged."
            @unknown default:
                notice = "The App Store returned an unknown purchase result. Please try again later."
            }
        } catch {
            notice = "The purchase couldn’t be completed. Please try again."
        }
        #endif
    }

    func restorePurchases() async {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        notice = nil
        defer { isRestoringPurchases = false }

        do {
            try await AppStore.sync()
            notice = "Purchase history refreshed. Consumable support purchases don’t unlock restorable features."
        } catch {
            notice = "Purchases couldn’t be restored. Please try again."
        }
    }

    func dismissThankYou() {
        isShowingThankYou = false
    }
}
