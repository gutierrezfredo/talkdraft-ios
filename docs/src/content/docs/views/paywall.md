---
title: Paywall
description: Subscription upgrade screen.
---

## Purpose

The paywall presents the Pro subscription, including the introductory trial when the current App Store account is eligible.

## Trigger Points

The paywall appears:
- During onboarding for new users
- From the standalone Pro upgrade flow when subscription access is needed

## Layout

- **Feature list** — compact list of Pro benefits
- **Trial timeline** — explains when access starts, reminder timing, and when billing begins
- **Pricing options** — monthly ($5.99/mo) and yearly ($59.99/yr) selection
- **Subscribe button** — initiates StoreKit 2 purchase flow
- **Restore purchases** — for users who previously subscribed

## Purchase Flow

1. User selects monthly or yearly plan
2. StoreKit 2 presents the system purchase dialog (Face ID / Touch ID confirmation)
3. On success: entitlement status is refreshed through RevenueCat
4. Pro entitlement activates immediately
5. The user continues into the app or returns to their previous action

## Related

- [Integrations](/architecture/integrations/) — StoreKit 2 + RevenueCat details
