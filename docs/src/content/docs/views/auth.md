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
| **Google** | OAuth flow via Google account. |
| **Email + Password** | Traditional registration with email and password fields. |
| **Anonymous** | Skip sign-in entirely. Data persists until the user creates an account. |

All methods are handled through Supabase Auth. Users can link additional providers to their account later.

## Post-Sign-In

After successful authentication:
1. User profile is fetched or created in the database
2. Notes and categories are loaded
3. Subscription status is synced with RevenueCat
4. The user lands on the [Home](/views/home/) screen

## Related

- [Getting Started](/getting-started/) — first-time setup guide
- [Settings](/views/settings/) — account management and deletion
