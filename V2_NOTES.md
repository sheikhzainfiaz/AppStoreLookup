# Applookup 2.0

## New tabs
- **Lookup** – the v1 report, plus a *Monthly earnings* card. If an ID isn't sold in the chosen
  storefront, a button sends it to Availability.
- **Availability** – checks all 175 App Store storefronts. Shows Live / Not live, the live
  listing, and every country it's sold in (grouped by region, filterable, shareable).
  Throttled requests are marked *Unconfirmed* and can be retried — never counted as "not live".
- **Earnings** – actual monthly earnings for your own apps via the App Store Connect API
  (last 6 months, per app, per storefront, downloads, IAP/subscription split).

## App Store Connect setup
1. App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys.
2. Generate a key with the **Sales** (or Finance) role. Download the `.p8` (one chance only).
3. In the app: Earnings → Connect. Enter Issuer ID, Key ID, vendor number
   (Payments and Financial Reports, top left), and import the `.p8`.
The key is stored in the Keychain on the device.

## Earnings estimates for other apps
Apple publishes no earnings for apps you don't own. The Lookup card estimates them from
Top Grossing rank and downloads, calibrated by *earnings anchors* — your own apps' real
proceeds in a storefront. Two anchors at different grossing ranks in the same storefront
fit the curve; one anchor gives a wider band. Estimates are per storefront, in USD proceeds.

## New files
Storefronts.swift · Availability.swift · AvailabilityScreen.swift · AppStoreConnect.swift ·
EarningsEstimate.swift · EarningsSection.swift · EarningsScreen.swift
(The project uses synchronized folders, so Xcode picks them up automatically.)
