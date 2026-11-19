# Store review access — Apple App Store / Google Play

This configuration is **not** a demo mode. It uses the existing email + 6-digit
code screen, ordinary server sessions, and the same seller authorization rules.
There is no public master code, no bypass URL and no in-app reviewer switch.

## Accounts to create (four independent identities)

| Store | App | Email (replace with dedicated mailbox) | Access |
| --- | --- | --- | --- |
| Apple | Buyer | `<apple-buyer-review-email>` | Buyer profile, favourites, search, chats |
| Apple | Seller | `<apple-seller-review-email>` | Pre-approved test shop and pavilion |
| Google | Buyer | `<google-buyer-review-email>` | Buyer functions |
| Google | Seller | `<google-seller-review-email>` | Pre-approved test shop and pavilion |

**Do not use the owner's personal email.** Use four addresses under a controlled
domain; do not connect any of these accounts to real sellers, customers,
messages or payment accounts. Do not put their emails or codes into Git, CI,
client code, release artifacts, or screenshots.

## Provisioning — only an operator on the target server

The database must be migrated with Alembic first. Provisioning is NOT automatic
on API startup. The operator supplies a randomly generated six-digit code via
a protected interactive terminal; the stored value is a salted PBKDF2 hash.
Use distinct codes for every account. In the examples replace values in angle
brackets with actual emails (omit brackets).

On the future VPS, execute within the existing API container's dependencies
using a **one-time helper** mounted read-only from the repository. No secrets
are placed in arguments, Compose variables, or git-committed files:

```sh
cd /srv/sadohod
# Once per reviewer account, repeat with apple/google and buyer/seller.
docker compose --env-file .env.production -f docker-compose.production.yml -p sadohod_public \
  run --rm -it --no-deps \
  -v "$PWD/tools/manage_review_accounts.py:/app/manage_review_accounts.py:ro" \
  api python /app/manage_review_accounts.py provision \
  --email reviewer-buyer@YOUR_DOMAIN --platform apple --role buyer --days 45
```

The process will prompt for the private code. Do not pipe code from plaintext
files. Transfer it only to the relevant private store-review access field.
After the review period, disable the reviewer and revoke every active session:

```sh
docker compose --env-file .env.production -f docker-compose.production.yml -p sadohod_public \
  run --rm -it --no-deps \
  -v "$PWD/tools/manage_review_accounts.py:/app/manage_review_accounts.py:ro" \
  api python /app/manage_review_accounts.py revoke --email reviewer-buyer@YOUR_DOMAIN
```

Rotation: repeat `provision` with the same platform/role/email, enter a *new*
code. The previous code and existing sessions become invalid. A different
platform/role must use a different email. The command refuses to convert a
regular customer's existing account. The server also caps code guesses to
five attempts per review email per hour, and twenty failed guesses over the
credential's lifetime; after excessive failures, rotate the reviewer code.

**Privacy and scope:** This is an explicitly provisioned test identity and may
have normal buyer functionality. Do not populate it with personal data,
private messages, customer photos or real stock. App review sessions expire
after at most 7 days and must be renewed via the private code if needed.
Production preflight/DEMO_SEED safeguards remain unchanged.

## Seller prerequisites (do not bypass moderation)

A seller login alone does not authorize the merchant operations. The existing
server requires *both* `ShopMembership(role=owner)` and an approved
`ShopRecord`; product listings additionally need a `PavilionClaim`.

For each reviewer seller, use the existing **admin-controlled** merchant
application/approval flow to prepare a test shop and a verified pavilion that
does not impersonate any real physical location. Do not create a fake
geographical address or occupy an actual third-party pavilion. If there is
no suitable verified test location available, use an isolated review/staging
dataset with a deliberately reserved review pavilion and keep it separate
from publicly visible marketplace catalogues; do not claim production
readiness until this has been tested in the release environment.

Confirm merchant readiness (the command returns failure until all requirements
are present):

```sh
docker compose --env-file .env.production -f docker-compose.production.yml -p sadohod_public \
  run --rm -it --no-deps \
  -v "$PWD/tools/manage_review_accounts.py:/app/manage_review_accounts.py:ro" \
  api python /app/manage_review_accounts.py check-seller \
  --email reviewer-seller@YOUR_DOMAIN
```

Create only a few clearly labeled TEST-only listings, with non-personal,
rights-cleared photographs; avoid public offers if the deployment cannot
isolate review content. Demonstrate pending moderation and approved
catalogue product paths without granting admin credentials to reviewers.

## Apple: App Store Connect → App Review Information

For each app, fill the private reviewer contact and Notes field:

**Buyer app**

> Email: <apple-buyer-review-email>
> Review code: <private 6-digit code supplied directly in App Store Connect>
> Steps: Open the app, tap Sign in, enter the email, tap Request code, then
> enter the supplied private review code in the usual six-digit field.
> This private reviewer code is not sent by email. No separate demo mode exists.
> Use the account to test favourites, messages and profile features.

**Seller app**

> Email: <apple-seller-review-email>
> Review code: <private code>
> Steps: Sign in using the ordinary email/code screen. The store and pavilion
> for this account have been approved in advance by our moderation team.
> Open My Stores, select the approved pavilion, then use Add Product and
> product management. A newly submitted item may require moderation.
> If the review needs a preapproved product, contact the review contact.

## Google: Play Console → App content → App access

Provide the reviewer email and a **repeatable private six-digit code** in
the protected App access instructions. Use the separate Google buyer/seller
identities rather than the Apple accounts. Google reviewers can repeat login
after logout or session expiry without waiting for email forwarding.

**Buyer instruction**

> Sign in with <google-buyer-review-email>. Tap Request code; use the
> reviewer-specific code shown in this private Play Console instruction.
> The app uses the same code entry UI as normal users. This code is only
> valid for the listed email and is not a general-purpose OTP bypass.

**Seller instruction**

> Sign in with <google-seller-review-email> and the corresponding private
> reviewer code. The test seller owns an approved shop/pavilion. Go to
> My Stores or Add Product. Product publication remains subject to ordinary
> safety moderation. No admin privileges are granted.

Store the *real* code only in App Store Connect / Play Console, not in this
document. After review, rotate or revoke these credentials and audit any
new test data. If a marketplace refuses a short reusable 6-digit credential,
consider a dedicated private review environment or account-specific
longer-secret flow rather than weakening the normal OTP authentication.

## Security checklist and limitations

- No public review-code generation endpoint; plain code never stored in DB.
- Ordinary OTP remains unchanged and uses SMTP, 10-minute expiry, five tries,
  and per-IP/email rate limits.
- Reviewer OTP request response never returns a code or causes an email send.
- Distinct reviewer codes for each store and role; rate limiting applies across
  IPs because the email-scoped rate bucket is stored in PostgreSQL.
- Disabling a reviewer invalidates active tokens immediately, even if their
  buyer email is later changed.
- Buyer delete is disabled for reviewer accounts; revoke via operator command.
- Reviewer sellers cannot bypass approval or take control of someone else's
  pavilion; no migration grants seller permissions automatically.
- Real Internet access, email delivery, store reviewer workflow, approved
  seller fixture and test data still need verification on a deployed HTTPS API.
