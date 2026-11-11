# ASSUMPTIONS.md — Meridian Payments Google Cloud Evaluation

**Status:** Day-one decisions made without customer responses. These are proposed delivery assumptions, not customer-approved requirements.  
**Input:** `CLARIFICATIONS.md` (original customer email; do not modify after its initial commit).  
**Decision principle:** Preserve the explicit exercise contract, prioritize non-negotiable security constraints, minimize the three-week evaluation footprint, and record production gaps rather than silently presenting the PoC as production-ready.

## 1. Decisions corresponding to every clarification

| ID | Clarification topic / unanswered question | Decision in the absence of an answer | Reasoning and risk / what would change it |
|---|---|---|---|
| A01 | **Evaluation success:** What constitutes success beyond an API-to-PostgreSQL connection? | Treat successful Terraform provisioning, a live public `GET /health`, a fresh Cloud SQL query and a fresh Secret Manager read per request as the acceptance criteria. Capture repeatable deployment and basic verification instructions. | These are directly measurable in the exercise. This does **not** demonstrate performance, disaster recovery or regulatory compliance. Revise if Meridian supplies other acceptance tests. |
| A02 | **Existing API or contract:** Reuse an existing container, or build a representative API? | Create a small synthetic HTTP API specifically for the evaluation. Do not assume access to Meridian source code or third-party integrations. | No application artifacts or contract were provided. Keep app logic deliberately minimal and avoid real payment data. |
| A03 | **Network/default VPC objection:** Must resources use the default VPC? | **Reject the default VPC proposal.** Create a dedicated custom-mode VPC and subnet in Terraform; use a private Cloud SQL IP with **no public IP**. | The requirement is private connectivity, not use of a particular default network. Dedicated networking makes isolation explicit. Any CIDR conflicts or organization standards would require a redesign. |
| A04 | **CIDRs / existing private connectivity / organization standards:** What ranges or standards already exist? | Assume a standalone demonstration GCP project with no overlapping network ranges, no organization policy restrictions, and no existing VPN/Interconnect. Make subnet/allocated IP ranges configurable and document them. | This is an evaluation account, not an actual enterprise landing zone. Confirm before applying in a real customer organization; overlapping ranges and organization policies could block deployment. |
| A05 | **Developer migrations:** Does “from laptops” mean direct database sessions or triggering an approved job? | Select **Option C: a developer-triggered Cloud Run Job**, executed in the private cloud environment using its own IAM identity and separate PostgreSQL migration role. The laptop triggers an approved, immutable migration artifact; it does not connect to the database. **Do not open a public database endpoint.** Document this as a proposed alternative, not proof that the literal laptop-connectivity requirement has been fulfilled. | It supports developer initiation without making the private database internet-reachable. **Execution from a laptop is not the same as execution on the laptop.** If direct laptop connectivity is mandatory, this choice requires reassessment. See `docs/DEVELOPER-MIGRATIONS.md` (ADR-001). |
| A06 | **Developer remote access:** Is VPN or other approved private access in place? | Assume **none** is available for the PoC. Do not provision a VPN or permit database access from arbitrary developer laptops. Under Option C, authorized developers may invoke the preconfigured Job, not edit or impersonate its runtime identity. | Private access needs enterprise identity, endpoint posture and network ownership inputs not supplied. This requirement remains **open / scope-limited** until approved by the customer. |
| A07 | **GitHub credential pattern objection:** Can we replace a long-lived JSON key? | **Reject service-account JSON keys.** If CI is implemented, configure GitHub OIDC → Google Cloud Workload Identity Federation with a short-lived identity and narrow Terraform permissions. | Avoids a long-lived credential and aligns with the exercise's credential constraint. External GitHub configuration/permissions must be provided or carefully documented. |
| A08 | **Repository ownership and IAM ownership:** Who controls GitHub and GCP privileges? | Assume a candidate-controlled GitHub repository and GCP project for evaluation. Use separate identities for CI deployment and application runtime; scope access by role and resource where feasible. | The real platform team's identity and trust setup is unknown. No broad organization-level access or impersonation of an existing Meridian service account. |
| A09 | **Synthetic data / regulated processing:** What data is used, and do PCI DSS, GDPR or contract controls apply? | Use **synthetic, non-sensitive test data only**; do not process real cardholder data or customer PII. Record PCI DSS / GDPR / contractual controls as a required customer review before production. | A payments company may have additional obligations, but the document supplies no data classification or compliance scope. A PoC is **not** a compliance attestation. |
| A10 | **EU residency:** Is an EU region acceptable? | Deploy in `europe-west1` (Belgium), consistently for the application and database; keep resources in one region for the PoC. | EU location is compatible with the stated Lithuania/Germany customer footprint as an initial technical assumption, not a legal finding about residency. Check organizational and contractual restrictions before production. |
| A11 | **US expansion:** US customers or US data residency? | Deliver one EU deployment only. Parameterize region and infrastructure names where useful, but do not pre-build US resources, replication or cross-border data movement. | Serving US customers is not the same as requiring US storage. Data residency, latency, legal and resiliency implications require a separate decision. |
| A12 | **Public API exposure and auth:** Is the whole API public? | Expose only `GET /health` as required for review; do not add unauthenticated business or payment APIs. Keep returned values strictly limited to the prescribed JSON keys. | The exercise explicitly requires a public URL; no real public application API or auth contract was supplied. Note that unauthenticated health probes can reveal operational status; restrict other routes. |
| A13 | **Secrets ownership and rotation:** Who provisions and rotates the database password and provider token? | Create Secret Manager **resources** with Terraform and use a dedicated application service account granted access only to the required secrets. Use synthetic/throwaway values for the PoC. Do not commit secret payloads, `.tfvars` containing values, credential JSON or `.env` files. | Demonstrates secret separation and runtime identity. **Important:** Terraform-managed secret versions may still put payloads in Terraform state; use carefully secured encrypted remote state or an injection method that avoids state exposure where supported, and clearly document the trade-off. Production ownership/rotation remain undecided. |
| A14 | **Third-party API:** Should the PoC call a provider? | No outbound third-party API requests. Store a placeholder test token as the second secret, and demonstrate an actual Secret Manager access on every `/health` request. | No provider, endpoint or credentials were provided; a real integration would be invented scope. Do not confuse successful secret retrieval with third-party integration testing. |
| A15 | **Availability / recovery:** What are SLA, RPO and RTO? | Use a single regional Cloud Run deployment and a deliberately low-cost Cloud SQL configuration sufficient for a working demonstration. Do **not** claim production HA or DR. Document production options: HA, automated backups, PITR, restore drills, failover and monitoring, subject to confirmed targets. | The exercise explicitly allows a non-HA implementation. Avoid inventing SLOs, RPO/RTO or claiming that untested controls work. |
| A16 | **Traffic / performance:** What load is expected? | Assume minimal demo traffic; no scaling or latency target is promised. Configure Cloud Run resource and instance bounds to prevent accidental spend. | Without traffic estimates, load testing or a meaningful capacity plan is unjustified. Reassess connection pooling, Cloud SQL capacity and scaling for production. |
| A17 | **Budget and production scope:** What is the target budget? | Favor the smallest supported configuration that meets functional requirements, set conservative scaling limits, and tear down **only after the review**. Track actual time worked and stop at five hours. | Cloud SQL and other resources may incur cost; free trial credit is not a guarantee that every chosen resource is free. Do not delete before the assessors review the live endpoint. |

## 2. Additional implementation assumptions and decisions

| ID | Decision | Rationale / qualification |
|---|---|---|
| I01 — Compute | Use **Cloud Run (service)** for a stateless container HTTP API. | Fits the small HTTP workload with low operational overhead. Document why GKE and Compute Engine are unnecessary for this slice. |
| I02 — SQL network implementation | Start with **private services access (PSA)** in the custom VPC and Cloud Run **Direct VPC egress** to the relevant subnet; do not assign public IPv4 to Cloud SQL. | A practical single-VPC PoC pattern. Google Cloud also supports and generally recommends **Private Service Connect (PSC)** for newer or more complex multi-VPC designs; reconsider if project/API/provider constraints favor PSC. Verify the actual path with a live SQL query. |
| I03 — Database access | Use a dedicated, least-privilege PostgreSQL application user and PostgreSQL connectivity over the configured private path. | Runtime IAM controls access to Google Cloud services; it does not automatically replace PostgreSQL authentication. Keep DB credentials in Secret Manager. |
| I04 — Runtime secrets | The `/health` handler reads a Secret Manager secret **when the request is handled**, not merely at process startup. | A startup-mounted environment variable alone is not enough to prove a fresh secret retrieval per request. Avoid returning the secret value or logging it. |
| I05 — Health contract | Return exactly `candidate`, `commit`, `region`, `db` and `secret`; only set the latter two to `"ok"` after current-request checks succeed. Handle failures without fabricating `"ok"`. | Implements the stated evaluation contract. Treat a failed dependency as an unhealthy response, with no extra output fields or secret-bearing diagnostics. |
| I06 — Commit traceability | Inject the **actual deployed source commit's short SHA** at build/deploy time, and validate it against the deployed revision/image. | A constant or latest local Git SHA that differs from the deployed artifact violates the contract. Document image version pinning. |
| I07 — Candidate name | Resolve `[Your Name]` to **exactly the name given to Commit** before deployment and final submission. | The brief requires an exact match; a guessed name would be a measurable failure. This is an outstanding input, not a fabricated assumption. |
| I08 — Terraform state bootstrap | Manage infrastructure with Terraform and store remote state in an access-restricted GCS bucket. Document the **state bucket bootstrap problem** and solve it through a repeatable Terraform bootstrap step, not by hand in the console. | Terraform cannot initially use a remote-state bucket that does not yet exist. A separate bootstrap configuration is acceptable as a proposed solution; ensure final application state is remote. Protect state because it may contain sensitive values. |
| I09 — Reproducibility | Pin Terraform/provider versions, make environment identifiers configurable, and document a short `init → plan → apply → validate` sequence. | Enables reviewers to understand and repeat provisioning; do not overbuild a framework. |
| I10 — CI/CD | Treat the GitHub Actions pull-request `terraform plan` as a **bonus**. Use WIF/OIDC, tight repository/branch trust restrictions and read-only-by-default PR permissions where practical; do not automatically apply unreviewed PR code. | CI is lower priority than the required live environment. A clear documented design is permitted for the bonus. |
| I11 — Secret bootstrap | The database must be configured using the same password that the runtime retrieves from Secret Manager; do not echo passwords in logs or include values in committed Terraform files. | Prevents a broken demo or accidental disclosure. If direct Terraform provisioning of secret versions is selected, acknowledge that marking inputs `sensitive` does not necessarily remove their values from state. |
| I12 — Delivery sequence and history | Commit the original `CLARIFICATIONS.md` **alone, before any code**, and leave it unchanged; add this file and implementation in later commits. | Commit explicitly checks history. If the initial commit already violates this order, do not rewrite history to misrepresent events—disclose the deviation. |
| I13 — AI use | Keep an append-only `AI-LOG.md` with **full, unedited transcripts** from each AI session (redact only credentials). Point to at least three genuine AI corrections/rejections in `README.md`. | Existing AI log is currently flagged **incomplete** and must be completed from the original chat before submission; invented examples or a summary do not satisfy the task. |
| I14 — Operations | Keep the API and GCP project running through review, provide the exact `/health` URL, and grant the specified reviewer Viewer access. | These are explicit submission requirements. Confirm viewer access without granting edit roles. |

## 3. Selected migration access decision

**Option C is selected for the evaluation:** developer-initiated, cloud-executed schema migrations through a dedicated Cloud Run Job. The approved execution artifact, dedicated job identity, separate PostgreSQL DDL role, Secret Manager access, private routing, narrow execution permissions, and PR/approval workflow are described in [`docs/DEVELOPER-MIGRATIONS.md`](docs/DEVELOPER-MIGRATIONS.md). **Documentation of this design does not imply the job has already been deployed.** Its implementation is secondary to the mandatory evaluation deliverables under the five-hour hard stop.

## 4. Explicitly unresolved customer decisions

The following are **not** claimed as implemented or approved merely because we documented fallback decisions:

- Direct, authenticated **laptop-to-private-DB** migration connectivity (A05–A06). A cloud-hosted migration job is a recommended alternative, pending confirmation.
- Regulatory scope and production data handling (A09–A11).
- Production SLO/SLA, RPO/RTO, backup, failover and sizing (A15–A17).
- Responsibility for production secret rotation and provider integration (A13–A14).
- The exact candidate-name string and the actual deployment SHA (I06–I07) must be populated from real inputs, not guessed.

## 5. Production delta to describe during review

Before production use, obtain approved architecture and controls covering IAM/service identities, private developer access, security monitoring/audit trails, TLS and database authentication, key/secret rotation, Cloud SQL HA/backup/PITR and tested restores, deployment promotion and approvals, resource budgets, operational SLOs and alerts, traffic estimates, regulatory obligations, and regional/data-residency requirements.

## 6. Technical reference points (validation, not customer answers)

- Cloud SQL connection options (PSA vs PSC): https://docs.cloud.google.com/sql/docs/postgres/connection-options
- Cloud Run to private Cloud SQL: https://docs.cloud.google.com/sql/docs/postgres/connect-run
- Cloud SQL private networking options: https://docs.cloud.google.com/sql/docs/postgres/private-ip
- Workload Identity Federation: https://docs.cloud.google.com/iam/docs/workload-identity-federation

These links support general GCP behavior. They do not resolve Meridian's unanswered business, security or compliance requirements.

---

## Architecture amendment — 2026-11-11: identity separation and Cloud SQL IAM login

**Status:** Supersedes any earlier PoC assumption that the API uses a built-in PostgreSQL username/password or that all Terraform steps run under a single unconstrained human identity. This update does not change the previously committed customer email.

- **Identity bootstrap:** An authorized administrator first provisions six distinct service accounts (Terraform deployer, API Cloud Run runtime, future migration Job runtime, and dev1/dev2/dev3) using `terraform/bootstrap`. The normal Terraform deployer receives role-specific infrastructure rights, but no Owner/Editor or project-level IAM administration.
- **Database authentication:** The API authenticates to Cloud SQL PostgreSQL using its runtime service account via automatic IAM DB authentication and short-lived credentials from the Python Connector. The API has `roles/cloudsql.client` and `roles/cloudsql.instanceUser`; Cloud SQL separately registers its IAM database user. Table and schema permissions require PostgreSQL GRANTs.
- **Developer access:** Human developers impersonate only their own developer service account. Once the approved Cloud Run migration Job exists, they will be allowed to execute that particular Job but not modify it or connect directly to SQL. The Job runs as a separate migration SA.
- **Acceptance trade-off:** The original exercise explicitly demands storing a database password and an API token in GCP. Removing the password in favor of IAM authentication is a **deliberate deviation** from that literal requirement, and the current PoC has just one API token secret. This must be discussed at review or reconciled before submission; do not claim all exercise requirements are satisfied.
- **Validation:** These changes exist as source configuration only. GCP IAM, Terraform plans, and actual database login are not validated yet.

For detailed rights and rationale see `docs/IAM-DESIGN.md`.


---

## Architecture amendment — 2026-11-11: reconcile two mandatory secrets with IAM authentication

**Decision (supersedes the previous one-secret deviation):** Provision two real secrets in GCP Secret Manager: (1) a password for the separate built-in PostgreSQL account `meridian_secret_user`, and (2) a synthetic external provider API token. The Cloud Run API reads **both** secrets per `/health` request under its own runtime SA, but its SQL `SELECT 1` uses **automatic IAM database authentication**, never the stored database password.

**Access decisions:** Give the Cloud Run API SA secret-level `roles/secretmanager.secretAccessor` for both secrets to meet the interview exercise. Give the **existing** Google Group named `db_secret_reader` read access to the DB-password secret only, after its real group email has been supplied; no project-wide secret-access grants. Do not grant developer SAs direct access.

**Rationale:** Preserve IAM-based runtime database access while demonstrating the exact two-secret health contract. The separate password account is valid, not an invented unused string, but should not be used in normal API operations.

**Trade-offs and limitations:** A runtime SA holding access to a password it does not need violates ideal production least privilege and must be explained as a PoC-specific trade-off. Terraform generates both secret values and therefore stores them in the GCS state. Restrict state access; replace Terraform-managed secret value seeding in production. The group is not auto-created as a project IAM object: Google Groups live in Cloud Identity/Workspace and require an actual email address.

**Validation:** The IAM group binding is skipped until `db_secret_reader_group_email` is provided. No GCP deployment or live validation has occurred. Detailed ADR: `docs/SECRETS-DESIGN.md`.


---

## Amendment — 2026-11-11: defer `db_secret_reader` until directory provisioning

The idea of a selected-users `db_secret_reader` Google Group is retained for a future production-shaped permission model but **is not implemented** in this PoC. The earlier conditional Terraform group binding and variable have been removed to avoid suggesting that a nonexistent directory group is active.

Once the organization has provisioned the real Cloud Identity/Workspace group and validated membership, a reviewed Terraform change could grant `roles/secretmanager.secretAccessor` to that group's actual email **on the DB-password secret only**. It must not grant project-wide Secret Manager access or database connectivity. The Cloud Run SA's two read permissions remain for the mandatory interview health check.

## Amendment — 2026-11-11: GitHub Actions rather than GitLab CI

The actual repository is `Comeon2022/CommitTask` on GitHub, and the original exercise specifies GitHub Actions. Therefore the PoC adds a GitHub Actions PR validation / plan workflow and a Terraform-managed GitHub OIDC Workload Identity Federation provider. This CI workflow is **not yet operational**: GCP project, bootstrap, repository variables and protected GitHub environment remain to be configured. GitLab CI would require a separate GitLab OIDC trust configuration and GitLab project.


---

## Technical review corrections — 2026-11-11

1. **PostgreSQL 16 / small machine edition:** Explicitly set Cloud SQL `settings.edition = "ENTERPRISE"` because PostgreSQL 16 defaults to Enterprise Plus, incompatible with `db-f1-micro`.
2. **Deployer service-account discovery:** `roles/iam.serviceAccountUser` assigned directly on the API and migration SAs includes `iam.serviceAccounts.get`, so project-wide `roles/iam.serviceAccountViewer` was deliberately not added. Live `terraform plan` must verify effective permissions.
3. **Human operator impersonation:** Bootstrap now supports a named human email `terraform_operator_email` and grants `roles/iam.serviceAccountTokenCreator` exclusively on the deployer SA, only when the actual email is supplied.
4. **EU secrets residency:** Both Secret Manager secrets now use one `user_managed` replica in `europe-west1` rather than unrestricted automatic replication.

These are source changes only, not claims of successful deployment or compliance certification. `CLARIFICATIONS.md` remains unchanged.


---

## Regional placement amendment — 2026-11-11

**Decision:** Deploy all region-configurable PoC resources in **`europe-west1` (Belgium)**. Both Terraform roots validate the region, and the GCS Terraform State bucket is now single-region `europe-west1` rather than `EU` multi-region. Cloud Run, Cloud SQL, subnet, Artifact Registry and both user-managed Secret Manager replicas use `var.region`.

**Exception:** GCP resources such as VPC network, global peering address, project IAM/service accounts and Workload Identity Federation are intrinsically global or project-scoped. Their location cannot be made regional. No deployment has been executed; location/compliance must be checked during plan and review.

See `docs/REGION-DESIGN.md`.


---

## Regional policy review — 2026-11-11 (supersedes the prior rigid-region amendment)

The `region` input remains an actual, controlled variable. Both Terraform roots allow only `europe-west1`, `europe-west3`, and `europe-west4`, with default `europe-west1`. All regional app/database/subnet/registry/secret replica components of **one deployment** still use the same `var.region`. This flexibility is **not** automatic multi-region hosting or failover; moving a deployed database or secret needs a planned migration.

Terraform State GCS is **reverted to `EU` multi-region**, a deliberate **exception** to application-region colocation: resilient state access and geographic EU redundancy matter more than keeping the backend in Belgium. Cloud Storage multi-region replication is asynchronous and does not guarantee immediate availability of the newest state revision after a regional failure. GCS state contains secret values generated by Terraform, so access and versioning controls remain essential.

The original customer mentioned prospective US customers, **not** a requirement to store data in the US. Any future US deployment requires a new approved location/residency decision and migration approach.

The separate independent Terraform roots each validate the same approved region list. This is intentional duplication, to be kept synchronized in code reviews. See `docs/REGION-DESIGN.md`. No deployment has been performed.


---

## Interview reviewer access — 2026-11-11

The Commit exercise requires Viewer access for `gcp-hr@comm-it.cloud`. To preserve least privilege, the privileged `terraform/bootstrap` root grants this exact user `roles/viewer` at the project `commitask` level. Do not add secret payload access or Terraform state object read roles: state contains both generated secret values. The IAM binding is **defined in source only** pending bootstrap apply and verification.


---

## Security audit — 2026-11-11: five reviewed findings

1. **Privileged PR CI:** Confirmed unsafe to let PR-editable workflows impersonate a full-write Terraform deployer. Removed the authenticated `plan` job from GitHub Actions and deleted the WIF deployer impersonation binding. PRs now run formatting and validation without cloud credentials. Trusted plan/apply remain manual until separate identities and approvals exist.
2. **GitHub OIDC identity literals:** Replaced repository name, repository ID and owner ID hardcoded in the provider with `github_repository_full_name`, `github_repository_id`, and `github_owner_id` input variables. ID examples remain documented for the current repository.
3. **Manual image / commit drift:** Added `scripts/prepare-release.ps1` to build from the current clean Git commit, label the image with its revision, push it, obtain its immutable digest and generate a single saved Terraform plan with image and SHA together. This script does not auto-apply and has not yet been executed.
4. **Unused identities/password:** The three developer SAs and migration runtime SA have no implemented migration Job workflow yet; they remain explicit scaffolding. The built-in PostgreSQL password account is deliberately not used for SQL login because the exercise requires two secrets while the API uses IAM DB authentication. These are accepted PoC trade-offs, not proof of runtime use. Follow-up: implement the migration job or remove unused identities before production.
5. **Root container:** Added a non-root `USER 10001:10001` to the Dockerfile. Actual Docker build/run verification remains pending.

This amendment supersedes previous text claiming PR Terraform plan/OIDC deployer impersonation is active. `CLARIFICATIONS.md` is not modified.


---

## Infrastructure/CI review — 2026-11-11: latest corrections

- **First image push:** The Artifact Registry repository was incorrectly defined in the PoC root and did not exist when `scripts/prepare-release.ps1` attempted to push. The registry is now provisioned in `terraform/bootstrap/artifact_registry.tf` with the regional root identity and a repository-specific Writer grant to the deployer. Removed the PoC registry resource and changed its output to a computed repository URL. No first-run `terraform -target` is needed.
- **Keyless local execution:** Release script now verifies the registry and token impersonation, and sets `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` and `CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT` for the deployer. The GCS backend is initialized with `impersonate_service_account` explicitly. No JSON key. Success remains unverified until run.
- **Plan-only CI:** A separate `meridian-poc-plan` SA gets project Viewer and IAM Security Reviewer plus state-bucket Object Viewer, and WIF impersonation ONLY on that SA. A manual, gated `workflow_dispatch` on protected `main` runs a read-only plan; PR validation remains credential-free. This is deliberately **not a PR plan**: the state contains generated secrets and even read-only state access can expose them. We prefer the narrower trusted-main flow over exposing state to untrusted PR code.
- **WIF cleanup:** Renamed the provider resource and provider ID from misleading PR names to trusted plan names (`github_main_plan` / `github-plan`); corrected comments and GitHub setup script.
- **Reviewer identity:** The external email `gcp-hr@comm-it.cloud` has not been confirmed as a directory user or group. New `reviewer_principal_type` input chooses `user` or `group`; default is user but the operator MUST confirm it before apply, to avoid a broken IAM binding.

No Terraform validation, cloud apply, image build, or CI job success is claimed. `CLARIFICATIONS.md` remains unchanged.


---

## IAM and Secret Manager plan review — 2026-11-11

- The deployer has `roles/iam.serviceAccountUser` *on the two exact service accounts* referenced by `data.google_service_account`; this includes `iam.serviceAccounts.get`. A project-level `roles/iam.serviceAccountViewer` was not added because it would expand IAM visibility needlessly.
- The trusted main-branch CI Plan SA has no `secretmanager.versions.access`. To avoid a normal Secret Manager secret-version refresh and additional secret IAM, the workflow uses `terraform plan -refresh=false`. This compares against cached Terraform state and is not a reliable drift-detection report. Any required runtime refresh or actual permission failures still need live validation. Manual authorized deployment uses the normal refreshed plan.
- Plan SA can read the state bucket, whose current values include generated secrets. Therefore read-only IAM is **not** proof of secret confidentiality. Restrict main/environment approvals and redesign secret-state handling for production.


## Artifact Registry least-privilege refinement — 2026-11-11

The regional Docker repository is created and IAM-managed by the privileged bootstrap root. The `meridian-poc-deployer` service account no longer has project-wide `roles/artifactregistry.admin`; it retains repository-scoped `roles/artifactregistry.writer` for publishing images. No extra Reader role is necessary for that publisher. Cloud Run's service agent image-pull access should be checked during first real deployment. These changes are committed but have not yet been applied or validated against GCP.
