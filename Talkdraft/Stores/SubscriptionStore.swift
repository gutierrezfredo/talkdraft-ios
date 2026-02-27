import Foundation
import Observation
import os
import RevenueCat
import StoreKit

private let logger = Logger(subsystem: "com.pleymob.talkdraft", category: "SubscriptionStore")

@MainActor @Observable
final class SubscriptionStore {
    var isPro = false
    var isLoading = false

    // StoreKit2 products fetched directly (RevenueCat offerings fallback)
    var monthlyProduct: StoreKit.Product?
    var yearlyProduct: StoreKit.Product?

    // MARK: - Limits

    var recordingLimitSeconds: Int { isPro ? 900 : 180 }
    var notesLimit: Int? { isPro ? nil : 50 }
    var categoriesLimit: Int? { isPro ? nil : 4 }

    var hasProducts: Bool { monthlyProduct != nil || yearlyProduct != nil }

    // MARK: - Configuration

    /// Call once at app launch, before any purchases.
    func configure() {
        Purchases.configure(withAPIKey: "appl_frykQRtNuFfPccuCcMLrDUvagyu")
        let adapter = DelegateAdapter(store: self)
        delegateAdapter = adapter
        Purchases.shared.delegate = adapter
    }

    // MARK: - User Sync

    func login(userId: UUID) async {
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId.uuidString)
            updateEntitlement(from: customerInfo)
        } catch {
            // Non-fatal — entitlement will be checked on next app launch
        }
    }

    func logout() async {
        do {
            let customerInfo = try await Purchases.shared.logOut()
            updateEntitlement(from: customerInfo)
        } catch {
            isPro = false
        }
    }

    // MARK: - Entitlement

    func checkEntitlement() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateEntitlement(from: customerInfo)
        } catch {
            // Keep current state on failure
        }
    }

    // MARK: - Products

    /// Fetch products directly from StoreKit2.
    func fetchProducts() async {
        do {
            let products = try await StoreKit.Product.products(
                for: ["talkdraft_monthly", "talkdraft_yearly"]
            )
            for product in products {
                switch product.id {
                case "talkdraft_monthly": monthlyProduct = product
                case "talkdraft_yearly": yearlyProduct = product
                default: break
                }
            }
            logger.info("Fetched \(products.count) products from StoreKit2")
        } catch {
            logger.error("StoreKit2 product fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    /// Purchase a StoreKit2 product and sync with RevenueCat.
    func purchase(_ product: StoreKit.Product) async throws {
        isLoading = true
        defer { isLoading = false }

        logger.info("Purchasing product: \(product.id)")
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                logger.error("Transaction verification failed")
                throw PurchaseError.verificationFailed
            }
            await transaction.finish()
            logger.info("Purchase succeeded, syncing with RevenueCat…")

            // Sync with RevenueCat so entitlement is granted
            let customerInfo = try await Purchases.shared.syncPurchases()
            updateEntitlement(from: customerInfo)

        case .userCancelled:
            logger.info("Purchase cancelled by user")

        case .pending:
            logger.info("Purchase pending approval")

        @unknown default:
            break
        }
    }

    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }

        let customerInfo = try await Purchases.shared.restorePurchases()
        updateEntitlement(from: customerInfo)
    }

    // MARK: - Private

    private func updateEntitlement(from customerInfo: CustomerInfo) {
        let active = customerInfo.entitlements["spiritnotes Pro"]?.isActive == true
        logger.info("updateEntitlement — isPro: \(active)")
        isPro = active
    }

    @ObservationIgnored private var delegateAdapter: DelegateAdapter?
}

enum PurchaseError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed: "Transaction verification failed"
        }
    }
}

// MARK: - Delegate Adapter

/// Bridges RevenueCat's NSObject-based delegate to our @Observable store.
private final class DelegateAdapter: NSObject, PurchasesDelegate, Sendable {
    private let onUpdate: @Sendable (CustomerInfo) -> Void

    init(store: SubscriptionStore) {
        self.onUpdate = { [weak store] customerInfo in
            Task { @MainActor in
                store?.isPro = customerInfo.entitlements["spiritnotes Pro"]?.isActive == true
            }
        }
    }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        onUpdate(customerInfo)
    }
}
