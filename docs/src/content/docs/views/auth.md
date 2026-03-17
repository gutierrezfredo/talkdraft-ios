---
title: Authentication
description: Sign-in and account creation.
---

## Purpose

The auth screen is the app's entry point for new and returning users.

## Sign-In Methods

| Method | Behavior |
|--------|----------|
| **Apple** | One-tap sign-in via Apple ID. Fastest option for iOS users. |
| **Email Magic Link** | Enter an email address and continue from the sign-in link. |
| **Guest** | Skip full account setup and continue with an anonymous session. |

All methods are handled through Supabase Auth.

## Post-Sign-In

After successful authentication:
1. User profile is fetched or created in the database
2. Notes and categories are loaded
3. Subscription status is synced with RevenueCat
4. New users continue into onboarding; returning users land on the [Home](/views/home/) screen

## Related

- [Getting Started](/getting-started/) — first-time setup guide
- [Settings](/views/settings/) — account management and deletion
