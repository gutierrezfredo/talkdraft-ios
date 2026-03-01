---
title: Paywall
description: Subscription upgrade screen.
---

## Purpose

The paywall presents the Pro subscription when a free user hits a limit (note count, recording length, or category count).

## Trigger Points

The paywall appears when a free user attempts to:
- Record beyond 3 minutes
- Create more than 50 notes
- Create more than 4 categories

## Layout

- **Plan comparison** — side-by-side Free vs Pro feature table
- **Pricing options** — monthly ($5.99/mo) and yearly ($59.99/yr) toggle
- **Subscribe button** — initiates StoreKit 2 purchase flow
- **Restore purchases** — for users who previously subscribed

## Purchase Flow

1. User selects monthly or yearly plan
2. StoreKit 2 presents the system purchase dialog (Face ID / Touch ID confirmation)
3. On success: purchase synced to RevenueCat via `syncPurchases()`
4. Pro entitlement activates immediately
5. Paywall dismisses and user returns to their previous action

## Related

- [Integrations](/architecture/integrations/) — StoreKit 2 + RevenueCat details
