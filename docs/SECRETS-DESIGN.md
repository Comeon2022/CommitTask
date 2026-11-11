# ADR-003 — Two Secrets with IAM Database Authentication

**Status:** Implemented in Terraform and API source. **Not deployed or validated.**  
**Date:** 2026-11-11.

## Decision

Meet the exercise's explicit two-secret contract **without** weakening the preferred database login model.

1. **`meridian-poc-db-password`** — contains an actual generated password for the built-in PostgreSQL user `meridian_secret_user` (separate from the API IAM database user). The API reads the secret on every `/health` request to demonstrate Secret Manager access, **but never uses this password to authenticate to PostgreSQL**.
2. **`meridian-poc-provider-token`** — holds a synthetic third-party API token for the evaluation. The API reads the secret on every `/health` request. It does not call an external provider.

The Cloud Run API continues to authenticate to Cloud SQL using **automatic IAM database authentication** through the Cloud SQL Python Connector under `meridian-poc-api`; it runs `SELECT 1` per request. Both secret reads must succeed and return nonempty payloads for `"secret":"ok"`. SQL query must succeed for `"db":"ok"`.

This reconciles the exercise's literal two-secret read requirement with the architect's choice to avoid passwords for runtime SQL login.

## Least privilege

| Principal | Database-password secret | Provider-token secret |
| --- | --- | --- |
| `meridian-poc-api` runtime SA | `roles/secretmanager.secretAccessor` on this secret only, required **solely by exercise health contract** | `roles/secretmanager.secretAccessor` on this secret only |
| Proposed future Google Group `db_secret_reader` | **Not implemented**; intended secret-level read access after directory onboarding | None |
| `meridian-poc-migration` SA | None | None |
| Developer SAs | None directly | None |

**Caveat:** Runtime visibility of a password it does not need is contrary to strict production least privilege. This is an intentionally scoped, exercise-only trade-off. In production we would **remove** the API's access to the unused password, and potentially eliminate the built-in DB user entirely, after acceptance requirements change.

## Google Group prerequisites

Google IAM supports `group:GROUP_EMAIL` on a secret resource. A display name like `db_secret_reader` is **not** an IAM principal by itself. The group must be an **existing Google Workspace / Cloud Identity Google Group** with an email address (for example `db_secret_reader@YOUR_DOMAIN`).

- **No group, group binding, or group variable is currently provisioned by Terraform.** This idea is documentation only.
- Directory administrators will create the group and manage selected members in Cloud Identity / Workspace.
- A future, separately reviewed Terraform change can grant `roles/secretmanager.secretAccessor` to `group:REAL_GROUP_EMAIL` on the **database-password secret only** once the group and its membership are verified.
- **Membership is not database access.** The group receives access only to Secret Manager's database-password secret. It is not registered as an IAM SQL database group.

## Risk: Terraform state and password-based user

- The password and synthetic provider token are created by Terraform resources. **Both plaintext values exist in sensitive Terraform state and GCS object history.** The `sensitive` UI flag does not remove secret payloads from state. Restrict GCS backend access, audit it, and delete evaluation resources after review.
- The built-in user has its own valid login credential: possession of the secret could permit login **if the attacker also has private network connectivity**. It is not an IAM SQL user, and should receive no additional SQL privileges. Default PostgreSQL privileges must be explicitly reviewed before production.
- Do not add secrets to app environment variables, logs, code, GitHub, or GitHub Actions secrets.
- For production, use a secret-seeding workflow outside Terraform and avoid retaining secret values in Terraform state; consider eliminating unused password-based accounts.

## Acceptance tests (not performed yet)

1. Confirm there are exactly two versioned Secret Manager resources and neither appears in code or plaintext outputs.
2. Verify each secret's IAM policy: API SA reads both; **no group access is implemented yet**; migration and developer SAs cannot read either.
3. Verify that disabling either secret version produces `"secret":"error"` and HTTP 503 on `/health`, independent of `db`.
4. Verify `SELECT 1` succeeds via IAM database authentication even if the legacy password is changed, as long as the secret health check remains healthy.
5. Confirm SQL instance has no public IP; prevent direct developer access.
6. Confirm secret payloads do not appear in Cloud Run logs; secure Terraform state.

See `CLARIFICATIONS.md`, `ASSUMPTIONS.md`, `docs/IAM-DESIGN.md`.


## Residency amendment — 2026-11-11

Both Secret Manager resources now use **user-managed replication with one replica in `var.region`, enforced as `europe-west1` (Belgium)**. The former `replication { auto {} }` allowed secret payload replication outside Europe. This is a documented EU-location assumption for the evaluation, not a formal GDPR/PCI compliance certification. The region is intentionally fixed to the selected EU PoC region until the customer approves a different data-residency plan. Replication location is immutable after secret creation; no deployment has occurred yet.
