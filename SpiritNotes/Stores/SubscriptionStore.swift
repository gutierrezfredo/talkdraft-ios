import Foundation
import Observation
import RevenueCat

@MainActor @Observable
final class SubscriptionStore {
    var isPro = false
    var currentOffering: Offering?
    var isLoading = false

    // MARK: - Limits

    var recordingLimitSeconds: Int { isPro ? 900 : 180 }
    var notesLimit: Int? { isPro ? nil : 50 }
    var categoriesLimit: Int? { isPro ? nil : 4 }

    var monthlyPackage: Package? { currentOffering?.monthly }
    var yearlyPackage: Package? { currentOffering?.annual }

    // MARK: - Configuration

    /// Call once at app launch, before any purchases.
    func configure() {
        Purchases.configure(withAPIKey: "test_YEeCDsYBasCAUveWcaPieBnCmiB")
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

    // MARK: - Offerings

    func fetchOffering() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            // Paywall will show without packages if this fails
        }
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws {
        isLoading = true
        defer { isLoading = false }

        let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
        if !userCancelled {
            updateEntitlement(from: customerInfo)
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
        isPro = customerInfo.entitlements["pro"]?.isActive == true
    }

    // Bridge to PurchasesDelegate (NSObjectProtocol requirement)
    // Cannot use lazy with @Observable, so we create it eagerly in configure()
    @ObservationIgnored private var delegateAdapter: DelegateAdapter?
}

// MARK: - Delegate Adapter

/// Bridges RevenueCat's NSObject-based delegate to our @Observable store.
private final class DelegateAdapter: NSObject, PurchasesDelegate, Sendable {
    private let onUpdate: @Sendable (CustomerInfo) -> Void

    init(store: SubscriptionStore) {
        self.onUpdate = { [weak store] customerInfo in
            Task { @MainActor in
                store?.isPro = customerInfo.entitlements["pro"]?.isActive == true
            }
        }
    }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        onUpdate(customerInfo)
    }
}
