# OKEYX Finalization Audit

**Status:** Active audit; this is a source-based baseline, not a release sign-off.  
**Audit date:** 2026-11-27  
**Repository:** `damnsenshi1/okeyx`  
**Base:** `main` at `3d743a1d4109c9603ed21ce6d858782383af2357`  
**Working branch:** `codex/okeyx-finalization` (latest audit commit recorded in the pull request)

## Executive summary

The repository contains a Flutter Android client and a FastAPI backend. The backend owns the Okey rules and multiplayer table state, exposes REST endpoints and WebSockets, and stores accounts through an `AccountStore` abstraction. Account state can use a Supabase PostgREST key-value table; live room state has a separate runtime snapshot path. The repository has a broad Python test suite and a small Flutter widget test suite.

The latest published mobile build is **20.7.0+270** (`v20.7.0-b270`). The latest `main` Actions run produced and published an APK. The available remote logs also show two analyzer warnings, nine Flutter tests passing, and an emulator smoke-test failure that was allowed to continue. A new pull-request workflow now runs backend tests and Flutter checks as blocking jobs. Its first PR run passed both jobs.

This is not a final readiness assessment. Production persistence configuration, transactional economy behavior, multiplayer recovery under failure, social/backend authorization, visual smoke tests, and Android release details still need deeper verification.

## Repository and architecture

| Area | Current implementation |
| --- | --- |
| Android client | Flutter under `mobile/`; package `com.senshilabs.okeyx_mobile`; `pubspec.yaml` version `20.7.0+270`; landscape game table and Android release workflow. |
| Backend | FastAPI under `backend/app`; account, game, legal, phase 4, operations and health routers. |
| Game engine | Server-side domain rules in `backend/app/domain/rules.py`; table actions in `backend/app/services/game_service.py`; runtime and matchmaking in `backend/app/services/game_runtime.py` and `backend/app/api/game.py`. |
| Multiplayer | REST actions plus `/game/{room_id}/ws`; rooms are held in process memory and restored from a runtime snapshot. |
| Account persistence | `AccountStore` writes locally when remote persistence is disabled; when enabled it loads Supabase KV rows and asynchronously flushes dirty rows. |
| Database | SQL migrations under `backend/migrations`; current checkout contains `001`, `002`, `019`, and `020`. |
| Hosting | Render Blueprint in `render.yaml`; Docker backend service; health check `/healthz`; free plan; generated runtime/admin secrets. |
| CI/release | GitHub Actions workflows under `.github/workflows`; `mobil_tur.yml` builds the APK and attempts an emulator screen tour. A PR quality workflow was added on this branch. |
| Tests | 39 Python test modules and 4 Flutter test files in the checkout. |

The root has no project-level README or `AGENTS.md`. `mobile/README.md` is still the generic Flutter starter text. `backend/app/main.py` advertises FastAPI version `16.0.0`, while the current Android package version is `20.7.0+270`; confirm whether this is an intentional API version or stale metadata.

## Baseline and quality evidence

### Remote baseline

- Latest `main` commit: `3d743a1d4109c9603ed21ce6d858782383af2357` (`20.7.0: yeni masa düzeni, düz ıstaka, bal ahşap`).
- Latest published release: `v20.7.0-b270`, APK asset present.
- Latest `main` workflow: APK build and release completed. Its test log reports **9 Flutter tests passed**. Flutter analysis reports warnings at `auth_service.dart:88` (`experimental_member_use`) and `table_screen.dart:7321` (`unused_element_parameter`).
- The same workflow's emulator screen-tour step reported `adb` failures (`emulator-5554` not found / connection refused), but that step has `continue-on-error: true`; the green workflow therefore does not establish a successful interactive startup or visual pass.
- The new PR run on this branch completed both **Backend tests** and **Flutter analysis and tests** successfully. The backend job installed `backend/requirements.txt` and ran `python -m pytest -q`; the mobile job ran dependency resolution, analysis, and `flutter test --reporter expanded`.

### Local environment

- A real shallow Git checkout now exists under the Codex workspace at `work/okeyx`; it tracks `codex/okeyx-finalization`.
- Git was not preinstalled. Portable MinGit is isolated under `work/mingit-setup`.
- Python is not installed in this Windows environment. The Windows Store `python.exe` alias cannot run.
- The installed Flutter CLI did not return from `flutter --version --machine` after repeated waits; those local Flutter commands were stopped. Local pytest, analyzer, widget tests, and Android builds have not been claimed as executed. GitHub Actions is currently the verified runner.

## Findings by severity

### P0 — Critical

- **None confirmed in the source review completed so far.** This is not evidence that the application has no P0 defects; the full authorization, economy, and production-data review is still open.

### P1 — Major / release blockers to resolve or verify

1. **Production account-store selection is not verified.** `render.yaml` declares the Supabase URL and publishable/anonymous key, but not the service-role key. `AccountStore` only selects remote KV persistence when the service-role setting is present. A dashboard secret may exist, but it has not been inspected. If it is absent, the backend falls back to local account storage on the free service, which is unsafe for durable balances and profiles. Verify the deployed environment and health/readiness behavior before release.
2. **Persistence is asynchronous and not a database transaction.** `AccountStore._save()` marks the remote store dirty; `RemoteSync` flushes changed KV rows in the background. The process-local lock does not serialize writes across backend instances, and there is a short crash window before a flush. Verify the current single-instance assumption and test recovery/concurrent balance changes before any scaling or paid-economy claims.
3. **The current Android smoke test is not a reliable release gate.** The latest run failed to find the emulator device, while the step was non-blocking. The APK build succeeded, but crash-free startup and the screen tour remain unverified. Diagnose the emulator runner and retain its failure as visible until it passes.
4. **The release workflow previously hid analyzer and test failures.** `mobil_tur.yml` had `continue-on-error: true` on both mandatory steps, and its output was piped through `tee` without `pipefail`. This branch removes those flags and enables `pipefail`. The PR quality workflow independently provides blocking backend and Flutter checks. Main-branch enforcement still depends on repository branch protection; GitHub currently reports `main` as unprotected.
5. **Gift retries are not idempotent.** The server enforces a 10-second per-room/player/gift cooldown and validates recipient/gift IDs. The current gift catalog sets every gift cost to zero, so the inspected direct-gift path does not charge currency. A retried request can still create duplicate social history/animations after the cooldown; no transaction ID or durable dedupe key is present. Preserve the existing free-gift business rule while deciding whether retry deduplication is required.

### P2 — Important technical debt / quality gaps

1. **Only a small part of the UI has automated coverage.** There are four Flutter test files; the latest workflow run reports nine test cases. The table, lobby, gift panel, profile, private-room flow, reconnect experience, and supported Android aspect ratios are not covered by the current widget suite.
2. **Analyzer warnings remain.** The two warnings listed in the baseline are visible in CI but allowed by the current Flutter analyzer command. Triage them and decide whether warnings should become blocking after cleanup.
3. **Migration history is incomplete in the checkout.** Only migration files 001, 002, 019, and 020 are present. Confirm the canonical production migration history and recovery procedure; do not infer that the missing numbers were never applied.
4. **Documentation does not describe the actual product or operations.** Replace the generic mobile starter README and document local setup, remote-store readiness, migrations, test commands, release signing, and rollback/recovery.
5. **Backend/mobile version metadata differs.** Confirm whether FastAPI's `16.0.0` is intentionally independent from Android `20.7.0+270`; align or document it.

### P3 — Polish

- Audit screen-reader labels, contrast, touch targets, low-memory behavior, and visual consistency after the game/lobby screens are rendered on representative Android sizes.
- Review asset sizes and release APK size after functional and reliability blockers are addressed.

## Economy and gift observations

- Gift identifiers, names, and prices come from the server-side `GIFT_CATALOG`; requests do not submit a client-selected price.
- All catalog gift costs are currently zero. This audit preserves that business behavior and does not introduce new prices or deductions.
- Table-wide gifts can call `STORE.debit`; that deduction and its notification/history behavior need concurrency and reconnect tests alongside match entry fees, settlement, rewards, purchases, and billing verification.
- Current tests include a gift cooldown test, but no test in the inspected suite demonstrates durable idempotent gift delivery or cross-instance atomic wallet updates.

## Execution order

1. Complete the Phase 01 source/security/data-flow audit and verify the production persistence configuration without changing production settings.
2. Establish and retain blocking backend/mobile quality checks; fix baseline failures before broad refactors.
3. Trace gift delivery, wallet mutations, game fees/settlement, purchase verification, and persistence under retry/concurrency; fix only confirmed defects and preserve existing economy rules.
4. Validate Classic and 101 rules against the repository's documented/locked choices and expand focused regression tests.
5. Review the live table/rack, gift, profile/social, lobby, and room flows on supported screen sizes; make targeted UI changes based on rendered evidence.
6. Exercise reconnect, room recovery, authorization, rate limiting, migration safety, and runtime persistence.
7. Run the complete regression suite and Android release build; resolve the emulator smoke-test failure and confirm release signing/configuration.

## Changes already present on this branch

- `.github/workflows/quality-gates.yml` runs backend pytest and Flutter analysis/tests on pull requests to `main` and pushes to `main` or this finalization branch. These jobs have no `continue-on-error` or shell failure suppression.
- `.github/workflows/mobil_tur.yml` now enables `pipefail` and no longer marks Flutter analysis or tests as non-blocking.
- Draft PR: https://github.com/damnsenshi1/okeyx/pull/1. Both new quality jobs passed on the first PR run before the release workflow edit; rerun status for the current head is pending.

## Remaining audit work

The source review of auth/session validation, account and economy routes, game action authorization, payment verification, room matchmaking/recovery, social actions, database policies, Android permissions, and screen layouts is incomplete. Production environment values, Render service state, Supabase policies/data, and device-rendered UI were not accessible in this audit pass. Do not treat this document as a release approval.



## Follow-up finding: action deduplication crossed seats

The room action cache was keyed only by the client-supplied request ID, while cached responses included the acting seat's private state. A different authenticated seat reusing the same ID could receive the first seat's cached response. The cache key is now scoped to seat and request ID, with an 80-character request ID limit. Regression coverage checks both private-state isolation across seats and same-seat retry idempotency. GitHub Actions validation for this follow-up is pending; this audit remains incomplete and is not release sign-off.
