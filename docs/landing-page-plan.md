# Landing Page Plan — Optimized for Trust

Status: **plan only, no code changes yet**
Companion to: `docs/distribution-plan.md` (§4 covers hosting/headers)
Supersedes the framing of the earlier draft; the underlying facts are unchanged.

---

## 1. The direction

**We optimize for a more trusting version of the society.**

This is not the softer option. It is the one that fits the actual growth model.

An invite is an act of social trust — the inviter spends their own reputation on
you. So the landing page has a job beyond converting a download: it has to make
the *invite* feel like something worth giving.

- **Fear-optimized page** → the invite reads as risk-transfer. "Let me warn you
  about this thing before you install it." Nobody forwards a warning to a friend
  they like.
- **Trust-optimized page** → the invite reads as a gift. "I use this and I want
  you to have it."

Your k-factor is therefore not just a conversion metric. **It is a direct
measurement of how much trust the product has earned.** `k > 1` means people
believe enough to spend social capital. That is the goal this page serves.

### The distinction that organizes everything below

| | Confidence | Trust |
|---|---|---|
| Built by | Proof, verification, evidence | Identity, commitment, consistency |
| Emotional register | Cool, analytical | Warm, relational |
| Reader's stance | Auditor | Acquaintance |
| Page feels like | A defense brief | An introduction |
| Outcome | "This probably won't hurt me" | "I believe these people" |

The earlier draft optimized for confidence. This one optimizes for trust.

**They are not in conflict** — verification still exists here. The change is that
proofs are *offered* rather than *argued*. You do not lead by rebutting accusations
the reader has not made. You lead by being legible, and leave the receipts where
anyone can find them.

> A page optimized for trust should read like an introduction, not a
> cross-examination.

---

## 2. What remains non-negotiable

Some friction is not the reader's opinion — it is imposed by the operating system,
and no amount of trust-building removes it. You must still handle these, because
the reader will meet them regardless of your tone:

| Imposed by | What happens | Why it can't be skipped |
|---|---|---|
| **Android** | Play Protect dialog appears mid-install | If it surprises them, they abort. Predicting it removes its power. |
| **Android** | "Allow this app to read SMS?" permission dialog | Appears whether or not you mention it. Silence reads as evasion. |
| **Google policy** | App is not on the Play Store | The absence is visible. It needs a reason. |

These are **logistics, not objections.** Handle them plainly, in the install
guide, where logistics belong — rather than elevating them into the hero as a
preemptive defense. The earlier draft led with the Play Store rebuttal as section
2; that primes an accusation the reader may not have been thinking about.

Better: state the reason once, calmly, in the section that explains what the
permission is for. Let it sit as context rather than as a courtroom exhibit.

---

## 3. How trust is actually earned here

Trust is not a copy problem. It is a behavior problem that copy can make legible.
Four mechanisms, in order of how much they carry:

### 3.1 Going first
The most reliable way to earn trust is to extend it before asking for any.

These are real properties of your current design — they are not claims, they are
things you have already chosen:

- **No account.** You are asking them for nothing to begin with. There is no
  sign-up wall, no email, no profile. *You* are trusting *them* first.
- **No email address.** You cannot email them, so you cannot spam them. Say this
  out loud — it is a gift, and most products cannot offer it.
- **No server copy.** Their data was never on your side to lose, sell, or leak.
  You could not betray it even if you wanted to.
- **Export, always available.** They are never locked in. Leaving is easy, so
  staying means something.
- **Uninstall = complete deletion.** Nothing remains anywhere.

Each of these costs you something (a growth hack, a marketing list, a lock-in
lever) and that is precisely why they are credible. Cheap promises persuade no
one. **These are expensive signals disguised as features.**

### 3.2 Identity before product
Trust starts with knowing who you are dealing with. Lead with a real person:

- Real name, real photo, a sentence about why this exists
- A real, monitored contact address
- A location, if you are comfortable — it costs nothing and adds a great deal

Anonymous developers can still be trusted, but they must work much harder, and
the source code plus hash combination carries less weight without a person behind
it. **If there is a name and a face available, use them above the fold.**

### 3.3 Commitments with consequences
"Here is our hash" is verification. "Here is what we promise, and what happens if
we break it" is accountability — and accountability is far rarer, therefore far
more persuasive.

A plain-language promise, first person, near the top:

> **What we promise**
>
> 1. Your data stays on your phone. It has nowhere else to go.
> 2. We do not have your email address, because we never asked for one.
> 3. You can export or delete everything in one tap.
> 4. We will not ship a network connection you did not ask for.
> 5. **If we ever break one of these, we will say so here first** — before you
>    hear it anywhere else.

Item 5 is the one that matters. Anyone can state principles. Stating the terms of
your own failure is almost never done, which is exactly why it lands. It also has
to be real — see §7.

### 3.4 Making the trust legible, not loud
The proofs from the earlier plan still exist. They move from the argument to the
invitation — a "for those who want to check" area rather than the headline:

- SHA-256 of the APK, with the command to verify it
- Link to source code
- The `INTERNET` permission claim
- The in-app network log

Framing matters more than presence:

> *"If you would like to check any of this yourself, here is how."*

Offered = confident. Argued = defensive.

---

## 4. Your strongest asset, restated

Facts (verified, unchanged from the earlier draft):

- `android/app/src/main/AndroidManifest.xml` declares only `READ_SMS` and
  `RECEIVE_SMS` — **no `INTERNET` permission**
- `INTERNET` appears only in the `debug` and `profile` manifests, which are
  separate build variants that release does not inherit
- `lib/` contains zero networking code

**The release build is denied network access by the operating system.**

The earlier draft framed this defensively: *"it cannot steal your data."* That is
an argument, and arguments invite counter-arguments.

The trust-optimized framing is a **design choice you made on their behalf**:

> *"We built it so your data has nowhere to go. The app has no internet
> permission — Android itself blocks it. We chose to give you that guarantee
> rather than ask you to trust our intentions."*

Same fact. Different posture: you went first.

### The conflict to resolve (distribution plan §5, §6)

Self-updating and invite crediting both require `INTERNET`, which would cost this
claim.

**Recommended: opt-in networking with an auditable log.**

- Fully functional with **zero connections** out of the box
- Networking happens only when the user taps "Check for updates" or "Claim invite
  reward" — never automatic, never background
- **Settings → Network log** listing every connection ever made: timestamp, host,
  exact payload
- Update payload is deliberately trivial: `{"versionCode": 12}` — one integer, one
  direction, once, only when tapped

Then the promise in §3.3 item 4 stays literally true, and the trust claim becomes:

> *"It makes no network connections unless you ask it to. Every one it has ever
> made is listed in Settings → Network log."*

This is the right resolution for this direction: it keeps the guarantee **and**
the functionality, by making the exception user-controlled and visible rather
than hidden.

---

## 5. Section-by-section architecture (trust-first order)

Sequencing logic: **identity → promise → what we're asking for → the product →
how to get it → how to leave.** That is the shape of a relationship, not a
sales funnel.

| # | Section | Job |
|---|---|---|
| 1 | **Who this is from** | Real name, photo, one line on why this exists. Establishes a person before a product. |
| 2 | **Hero** | The outcome, not the feature list. Real app screenshot. CTA above the fold. |
| 3 | **The promise** | §3.3 — five commitments, first person, including the failure term. |
| 4 | **What we're asking for** | The SMS permission: what it reads, what it never touches, and *why we ask this of you at all*. The Play Store reason lives here, calmly, as context. |
| 5 | **Where your data goes** | Nowhere — and here is how you'd confirm that yourself. |
| 6 | **What this does badly** | Honest limits. See §6.1. |
| 7 | **What it looks like** | 3–4 real screenshots, captioned. |
| 8 | **A gift, from Alex** | The invite reward, framed as something given to them. See §6.2. |
| 9 | **Install guide** | 3 steps with real Play Protect and SMS-permission screenshots. Logistics live here. |
| 10 | **Leaving is easy** | Export, delete, uninstall — promoted, not buried. |
| 11 | **For those who want to check** | Hash, source, permission listing, network log. Offered, not argued. |
| 12 | **Final CTA** | Same button, same words as §2. |
| 13 | **Contact** | A real person reads this address. |

**Mobile is the only design that matters.** Traffic arrives from a share tapped on
a phone. Everything above must work in a thumb-scroll at 390px, with what it is,
why it's safe, and the install button above the fold.

---

## 6. Two sections worth writing carefully

### 6.1 What this does badly

Keep this from the earlier draft — it survives the reframing intact, because
voluntary flaw disclosure is a trust behavior, not a fear tactic.

> **What this app does badly**
>
> - It needs SMS permission, and that permission is broad. Android has no narrower
>   way to read a bank alert — we did not choose the size of it.
> - There is no account recovery. Your data is on your device only, so uninstalling
>   removes it permanently. That is the trade for it never leaving your phone.
> - It cannot reach your bank directly. It only knows what your bank texts you.
> - The background listener is cheap, but it is not free.

**This costs you almost nothing and buys the most trust on the page.** A reader
who finds a disclosed weakness stops looking for hidden ones. Do not soften it
into marketing language — the bluntness is the signal.

### 6.2 The invite, as a gift

Your reward model is share-to-unlock-premium. Framing decides whether this reads
as generosity or extraction:

| Extractive | Gift |
|---|---|
| "Invite friends to unlock premium" | "Alex unlocked this for you" |
| The user is asked to *work* for the reward | The user *receives* something |
| Feels like a paywall with extra steps | Feels like being thought of |

Lead with what they got. Only after that explain that they can do the same for
someone else.

**Disclose the reward model openly on the page.** If someone discovers the
premium feature exists only behind invites *after* installing, the mechanic reads
as a hostage situation — and in a trust-optimized model, that single surprise
reverses the entire premise. Surprise turns a gift into a resentment.

---

## 7. The discipline this direction imposes

Optimizing for trust **raises the standard you must actually meet.** Trust is
cheap to offer and catastrophic to break, and a broken commitment costs far more
than never having made one. This is not an argument against the direction — it is
the condition that makes it work.

Concretely:

- [ ] **The five promises must all be literally true.** Not approximately. Each
      one is now a published commitment you can be held to.
- [ ] **Item 5 requires a real mechanism.** "We will say so here first" means the
      changelog is public, current, and updated *before* users notice the problem.
      If you cannot commit to that, cut the sentence — a broken accountability
      claim is worse than no claim.
- [ ] **No dark patterns, by definition.** See §8 — in this framework they are not
      taste violations, they are breaches of the promise.
- [ ] **The network log must be complete.** If it ever omits a connection, you
      have broken promise #4 in a way that is trivially discoverable.
- [ ] **Reviews and complaints get answered.** There is no store listing to
      absorb them; your public responsiveness *is* your reputation.

Also worth naming honestly: **trust-optimizing makes you a better target for
bad-faith criticism**, because you published standards. That is acceptable — the
alternative is publishing nothing and being judged on silence.

---

## 8. What does not belong on this page

Reframed from the earlier draft: these are not "tactics I dislike." In a
trust-optimized model they are **violations of your own promise**, which is a
much stronger reason to exclude them.

| Tactic | Why it's excluded here |
|---|---|
| Fake download counters, ratings, awards | Fabricated proof contradicts the promise to say so first when something is wrong |
| Invented testimonials | Spending someone else's fictional reputation is the inverse of the trust you're asking for |
| Fake urgency / countdowns | A free, always-available download cannot honestly be scarce |
| Confirmshaming ("No, I hate saving money") | Treats the reader as a mark. You need them to like you enough to invite a friend |
| Pre-checked marketing consent | Unnecessary — you are not collecting the email address in the first place |
| Hidden paywall after install | Direct breach of §6.2 and promise #3's spirit |

Note that **§7's discipline and this list are the same list.** That is the point:
in this model there is no gap between ethics and conversion strategy.

---

## 9. Measurement

**Funnel:**
```
page view
  → tap download
    → APK download completed        (Render request logs / analytics)
      → app installed               (first-launch ping — needs §4 networking)
        → day-7 retained
          → invite sent             ← the trust metric
```

**K-factor** — and per §1, read it as a trust measurement, not just a growth one:

```
k = (invites sent per user) × (invitee conversion rate)
```

- `k < 1` — people do not trust you enough to spend social capital on you
- `k > 1` — they do; growth compounds

**Trust-specific signals worth watching:**

| Signal | What it tells you |
|---|---|
| Invite rate | Willingness to stake reputation — the purest trust measure available |
| Day-7 retention after invite | Whether the trust transferred, or only the click |
| Flaw-disclosure section scroll depth | Whether honesty is being read or skipped |
| "For those who want to check" click-through | Whether verification is reassuring the undecided, or irrelevant |
| Uninstall / delete-data rate | Whether a promise was felt to be broken |

---

## 10. A/B tests worth running

1. **Identity-first (section 1) vs. hero-first.** Does putting a real person
   above the product help or hurt? My expectation: helps with invites, possibly
   neutral on raw installs.
2. **Promise section present vs. absent.** Is a published commitment read as
   confidence or as over-claiming?
3. **Flaw disclosure present vs. absent.** Expect a small install cost and a
   measurable retention gain — that is a trade worth taking.
4. **Play Store reason: in the permission section vs. immediately under the
   hero.** §2 argues for the quieter placement; test it rather than assume.
5. **CTA wording:** "Install" vs. "Get the app" vs. "Download APK" — the last
   sets the most accurate expectation for what will happen next.

Run one at a time. With low early traffic, prefer versions defensible on first
principles over waiting for significance that will not arrive.

---

## 11. Open questions

1. **Is there a real name and face to put on it?** §3.2 and the whole identity
   section depend on this. If anonymity is required, the plan still works but
   leans harder on source, hash, and the network log.
2. **Will the source be public?** If not, §11's verification section needs a
   different spine — the `INTERNET` claim and network log do not require open
   code and become your primary evidence.
3. **Can you commit to promise #5?** A public, current, honest changelog that
   leads with your own failures. If not, cut the sentence rather than risk it.
4. **Premium feature definition** — still open from distribution plan §9. The
   page must describe the gift in §6.2 accurately, so this blocks the copy.
5. **Is the page in the same repo as the app?** If so, keep the APK out of git
   history (distribution plan §4).

---

## 12. Suggested order

1. **Confirm the `INTERNET` decision** (§4) — it determines the headline trust
   claim and promise #4.
2. **Define the premium feature** (§11.4) — the gift has to be describable.
3. **Write sections 1–5** — identity, hero, promise, permission, data. These
   carry most of the trust weight.
4. **Write the flaw disclosure** (§6.1) — highest trust-per-word on the page.
5. **Build the install guide** with real Play Protect and permission screenshots
   (§5.9) — the only place logistics belong.
6. **Stand up the network log** (§4) before driving traffic — it is both a
   feature and the evidence for your central claim.
7. **Instrument the funnel** (§9) before the first share goes out.
