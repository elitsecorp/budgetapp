# Distribution Plan — Sideload + Viral Invites

Status: **plan only, no code changes yet**
Host decision: **Render (static site)**
Invite reward: **premium feature unlock**

---

## 0. Why this is forced, not chosen

`android/app/src/main/AndroidManifest.xml` requests `READ_SMS` and `RECEIVE_SMS`.

Google Play's Restricted Permissions policy only grants those to apps whose *core*
function is SMS. A budgeting app reading bank-alert SMS does not qualify, so Play
approval is not on the table. Sideloading is the only viable channel.

That constraint buys real things:

| | Play Store | Sideload |
|---|---|---|
| SMS bank-alert ingestion | Rejected | Works |
| Background `SMS_RECEIVED` listener | Restricted | Works |
| Release cadence | Days of review | Immediate |
| Update rollout | Staged, reversible | You own it |
| Install source trust | Google | **You** — this is the cost |

The cost is that **you** become the update authority. Everything below exists to make
that survivable.

---

## 1. Architecture

```
                    ┌──────────────────────────────────────┐
   share sheet ───► │  Render STATIC SITE (free, CDN)      │
   invite link      │  · /index.html   landing + install   │
   QR code ───────► │  · /i/<CODE>     invite page         │
                    │  · /budget-app.apk                   │
                    │  · /version.json  update manifest    │
                    │  · /.well-known/assetlinks.json      │
                    └──────────────┬───────────────────────┘
                                   │ (gap — see §6)
                                   ▼
                    ┌──────────────────────────────────────┐
                    │  referral crediting endpoint         │
                    │  needs to NOT sleep — open choice    │
                    └──────────────────────────────────────┘

   Flutter app ──── share_plus  → native share sheet
                ──── package_info_plus + poll /version.json → self-update
                ──── first-launch entitlement store (premium)
```

Render static sites **never spin down** — that's the whole reason they're the right
pick here. Render *free web services* sleep after 15 minutes idle and take ~60s to
cold start, which would be fatal for a share link tapped out of WhatsApp.

---

## 2. Phase 0 — Release signing (blocking, do first)

`android/app/build.gradle.kts:36` currently signs release builds with the **debug**
key. For a sideloaded app the signing key *is* the update identity: Android refuses
to install an update over an app signed with a different key.

**If this key is lost, every installed copy is stranded** — users must uninstall and
reinstall, destroying their budget data.

- [ ] `keytool -genkey -v -keystore budget-app.jks -keyalg RSA -keysize 2048 -validity 10000 -alias budget`
- [ ] Move credentials to `android/key.properties` (gitignored) — **not** hardcoded in `build.gradle.kts`
- [ ] Add a real `signingConfigs.release` and point `buildTypes.release` at it
- [ ] Add `key.properties` + `*.jks` to `.gitignore` (verify — it isn't there yet)
- [ ] Back up the keystore in **two** places: password manager + an off-machine copy
- [ ] Record the keystore password and the key password separately

Never rotate this key. There is no migration path.

---

## 3. Phase 1 — Build pipeline

- [ ] `flutter build apk --release --split-per-abi` — roughly halves download size vs. a fat APK
- [ ] Decide whether to ship `arm64-v8a` only (most devices since ~2017) or also `armeabi-v7a`
- [ ] Add a **build script** that: builds, computes SHA-256, stamps `version.json`, copies the APK into the site folder

**versionCode discipline is critical.** Android hard-rejects installing a lower
versionCode over a higher one, and sideloaded users have no Play console to bail them
out. `versionCode` comes from `pubspec.yaml` `version:` → bump on every single
release, never reuse.

`version.json` shape:

```json
{
  "versionName": "1.2.0",
  "versionCode": 12,
  "minInstallVersion": 4,
  "url": "https://<domain>/budget-app.apk",
  "sha256": "…",
  "sizeBytes": 18432000,
  "notes": "Fixes duplicated bank alerts",
  "releasedAt": "2026-11-25"
}
```

`minInstallVersion` lets you force an update when an old build has a data-corruption
or security bug — you cannot patch a shipped APK, so this is your only lever.

---

## 4. Phase 2 — Render static site

Static sites are free, served from a global CDN, support custom domains on the free
tier, and **do not sleep**. Response headers are configured in Dashboard → Settings →
Headers, or via the Blueprint `headers` field.

Headers that matter:

```yaml
headers:
  - path: /*.apk
    name: Content-Type
    value: application/vnd.android.package-archive
  - path: /*.apk
    name: Content-Disposition
    value: attachment; filename="budget-app.apk"
  - path: /version.json
    name: Cache-Control
    value: no-cache, max-age=0
  - path: /*
    name: X-Content-Type-Options
    value: nosniff
  - path: /*
    name: Referrer-Policy
    value: strict-origin-when-cross-origin
```

The `Content-Type` line is not optional. Without it Chrome on Android downloads the
APK as `.zip` and the install fails with "can't open file."

Landing page requirements — these directly drive install completion:

1. **3-step visual install guide** with screenshots. The "allow unknown apps" toggle
   is where most people bounce.
2. **Pre-warn about Play Protect.** Sideloaded APKs commonly trip
   "blocked by Play Protect." Show the exact dialog and where to tap
   *Install anyway*. Not warning about this costs a large share of installs.
3. State the app's permissions up front and *why* — SMS access reads badly if it
   appears unannounced in an install dialog. Framing it as "reads your bank SMS
   alerts so you don't have to enter transactions" converts far better.
4. SHA-256 fingerprint displayed, for people who verify.
5. Never-cache `index.html`; cache the APK aggressively.

**APK artifact storage:** Render deploys from git. A ~18 MB APK committed every
release bloats history quickly. Prefer a `distribute/` folder whose build step
overwrites the APK, or Git LFS. Keep `docs/` and the site in the same repo only if
the APK stays out of history.

---

## 5. Phase 3 — Self-update (non-negotiable)

No Play means no auto-update. Without this you get an unending stream of "how do I
update?" and, worse, no way to ship a security fix.

- [ ] `REQUEST_INSTALL_PACKAGES` permission in the manifest
- [ ] `package_info_plus` to read current `versionName`/`versionCode`
- [ ] Poll `/version.json` on launch + on resume, debounced
- [ ] Download APK to app cache, verify `sha256` **before** handing to the installer
- [ ] Hand off via `Intent.ACTION_VIEW` with `application/vnd.android.package-archive`
- [ ] Handle the "your device doesn't allow installing from this source" path —
      deep-link to `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES`
- [ ] Optional: background download with a notification, since updates can be large

Never auto-install without an explicit user tap — Android requires it anyway, and
surprising someone with an installer dialog reads as malware.

---

## 6. The gap: referral crediting needs a server

This is the one place the plan does not fit cleanly into a static site.

A static site **cannot run code at request time**. So `/i/<CODE>` can render a page
and even redirect, but it cannot *record* that `CODE` was used. And without recording,
you cannot credit the inviter — which is the entire point of the reward.

Attribution is additionally complicated by the fact that the **Play Install Referrer
API does not exist** for sideloaded installs. There is no free ride.

Three ways through, in increasing effort:

### Option A — Client-side crediting, no redirect logging (recommended to start)
- Invite link `https://<domain>/i/<CODE>` is a static page: shows "Alex invited you",
  stores `CODE` in `localStorage`, starts the download with `?ref=<CODE>` appended.
- After install, the app is opened **via the same URL** using an Android App Link
  (requires `/.well-known/assetlinks.json` on your domain). The intent carries `CODE`.
- The app POSTs the code to a redeem endpoint and stores the entitlement locally.

Cost: the invitee must tap the link a second time to open the app, or you prompt
"Tap to open" on the landing page once installed. Conversion loss, but zero
redirect-logging infrastructure.

### Option B — Static site + a non-sleeping redirector
Put only the `/i/<CODE>` redirect on a tiny always-warm endpoint that logs and
302s to the APK. Cloudflare Workers (free, 100k req/day, never sleeps) fits. Render's
*free web service* does **not** — 60s cold start on a share link is unacceptable.

Cost: a second platform. Best attribution quality.

### Option C — Render web service for everything
Single platform, real backend, real database. But free instances sleep after 15 min
and have ephemeral filesystems — you'd need paid compute, and this is meant to be a
free distribution channel.

**Recommendation:** ship **Option A** to validate that people actually share at all,
then move to **Option B** once invite volume justifies it. Do not start with C.

---

## 7. The viral loop

### Mechanics
- [ ] `share_plus` for the native share sheet — WhatsApp, Telegram, SMS. This is
      where the audience for a personal-finance tool actually forwards things.
- [ ] Per-user invite code (short, case-insensitive, unambiguous — avoid `0/O`, `1/I/l`)
- [ ] QR code on the invite page and in-app, for in-person and word-of-mouth
- [ ] Both-sides reward: inviter *and* invitee get the premium unlock
- [ ] Share prompt placed at a moment of satisfaction, not on launch — after a
      savings goal is hit or a month closes under budget

### Budget-app-specific hooks (strongest first)
1. **Partner / household budget** — one invite creates two permanently linked
   accounts. Highest-quality virality: the invitee is not a random, they're the
   person who shares finances with the inviter. Also the most natural premium paywall.
2. **Split-a-bill** — needs a second person by definition.
3. **Savings challenge between friends** — recurring, so it re-triggers.
4. **Milestone card** ("saved $500 this month") — classic share-image vector, but
   **financial data is sensitive**. Must be opt-in, anonymized by default, with no
   real balances or account names in the rendered image.

### Anti-abuse
Invite rewards are trivially farmable if not gated. Minimum viable protections:
- One premium claim per device install (`ANDROID_ID`-scoped, or your install ID)
- Codes are single-use for the *reward*, unlimited for the *link*
- Cap rewards per inviter
- Do not let a user invite themselves — bind claim to an install that did not
  previously exist
- Rate-limit the redeem endpoint

Local-only entitlement storage is more robust than it looks: repackaging the APK to
flip a flag breaks your signature, and Android then refuses to install it over the
original — the user would have to uninstall first and lose their data. That's decent
protection against casual tampering, and it's **free**, since you already committed
to strict signing in §2. Add server-side entitlements only when you need to revoke,
sync across devices, or sell.

---

## 8. Risks and gotchas

| Risk | Impact | Mitigation |
|---|---|---|
| Keystore lost | **Catastrophic** — all installs stranded | §2 backups, two locations |
| `versionCode` not bumped | Users can't update | Bump in `pubspec.yaml` every release; automate in build script |
| Missing `Content-Type` header | APK downloads as `.zip`, install fails | §4 headers, test on a real device |
| Play Protect blocks install | Big install drop-off | Landing page pre-warns, shows "Install anyway" |
| "Unknown sources" confusion | Highest bounce point | 3-step visual guide with screenshots |
| Static site can't log referral clicks | Can't credit invites | §6 — Option A first |
| Users don't know how to update | Support burden, stuck on buggy builds | §5 self-updater |
| SMS permission reads as spyware | Installs rejected at the dialog | Explain up front on landing page |
| APK in git history | Repo bloat | `distribute/` folder or Git LFS |
| App data loss on reinstall | Churn + bad word-of-mouth | Strong §2 signing so updates never need reinstall |

**Distribution-licensing note:** sideloading avoids Play's review, but the SMS
permissions still require the user's informed consent at runtime. Get it right in
the UI — a budgeting app that quietly reads SMS is exactly the pattern that gets
apps flagged and projects killed, independent of any store policy.

---

## 9. Open questions

1. **What is the premium feature?** The reward is the whole loop; it needs to be
   defined before the entitlement code can be written. Partner/household budgets are
   the obvious candidate — the invite *is* the feature unlock.
2. **Custom domain?** You need one for App Links (`assetlinks.json` verification
   requires a domain you control). Render includes 2 free on the Hobby plan.
3. **Which ABIs to ship?** arm64-only keeps the download small.
4. **Is there a backend at all yet?** Everything here assumes none. If one appears,
   §6 Option C becomes cheaper.

---

## 10. Suggested order

1. **§2 Signing** — nothing else works until this is right, and it's the one step
   where a mistake is unrecoverable.
2. **§3 Build** — produce a real, installable release APK.
3. **§4 Render site** — get it onto a device via a plain link.
4. **§5 Self-update** — before any real distribution, or you can't fix what ships.
5. **§6 + §7 Viral loop** — only once installs actually work end to end.
6. **§8 Anti-abuse** — with the reward, not after it's being farmed.
