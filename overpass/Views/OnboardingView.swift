import StoreKit
import SwiftUI

struct OnboardingView: View {
    @AppStorage("sh.dunkirk.overpass.onboarding_shown") private var onboardingShown = false
    private let store = StoreManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                VStack(spacing: 6) {
                    Text("Overpass")
                        .font(.largeTitle.bold())
                    Text("Find the cheapest gas near you.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("I strongly feel that you should never have to make a decision on whether you want to buy something without trying it first so you have complete access for the next 15 days! Try it and hopefully you will love it but if not then you don't have to pay a dime :)")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 16) {
                Button {
                    onboardingShown = true
                } label: {
                    Text("Go find some gas!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)

                Text("15-day free trial, then \(store.product?.displayPrice ?? "$2.99") once. No subscription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider()
                    .padding(.vertical, 4)

                Button {
                    Task {
                        try? await store.purchase()
                        if store.isUnlocked { onboardingShown = true }
                    }
                } label: {
                    if store.isPurchasing {
                        ProgressView()
                    } else {
                        Text("Buy Now — \(store.product?.displayPrice ?? "$2.99")")
                    }
                }
                .font(.subheadline.weight(.medium))
                .disabled(store.isPurchasing || store.product == nil)

                Button("Restore Purchase") {
                    Task {
                        await store.restore()
                        if store.isUnlocked { onboardingShown = true }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .interactiveDismissDisabled()
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { onboardingShown = true }
        }
    }
}


