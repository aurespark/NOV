# ADR 0001: Android WebView DOM and Foreground Download Notification

Status: Accepted for M0 technical verification

Date: 2026-07-30

## Context

The online-novel workflow needs two Android capabilities later in v6:

- Read the rendered DOM for sites that cannot be parsed from raw HTML.
- Keep long chapter downloads visible while the app is foreground/background.

## Decision

Use Android WebView for rendered-page probing and a foreground-service-backed notification for long downloads.

For M0, this repository only records the feasibility decision and keeps the shipped app behavior unchanged. The implementation belongs to later milestones where WebView lifecycle, permissions, cancellation, and retry state are specified.

## Verification

- Web catalog parsing is covered by `test/m0_baseline_test.dart` using a local fixture.
- The Android project already targets a normal Android app module, so native platform code can be added under `android/app/src/main/kotlin` when the download worker milestone starts.
- Foreground notification work must include Android 13+ notification permission handling and a non-bypassable TLS policy before release.

## Consequences

- No new dependency is added in M0.
- Later work should add the WebView/foreground service code at the first milestone that actually uses it.
