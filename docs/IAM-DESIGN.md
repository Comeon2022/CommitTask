# ADR-002 — Identity and Least Privilege

**Status:** Implemented in Terraform source, unvalidated and not deployed.  
**Decision date:** 2026-11-11.

## Principals

| Identity | Scope | Intended access |
| --- | --- | --- |
| `meridian-poc-deployer` | Terraform only | Functional project-scoped administrators for network, SQL, Run, Artifact Registry, Secret Manager and API enablement; `iam.serviceAccountUser` on the exact runtime SAs. No Owner/Editor/project IAM Admin. |
| `meridian-poc-api` | Cloud Run service | `cloudsql.client`, `cloudsql.instanceUser`; read the provider-token and database-password secrets at runtime for the exercise's two-secret health check (though SQL login uses IAM, not the password). Database access uses Cloud SQL IAM DB auth. |
| `meridian-poc-migration` | Future migration job | `cloudsql.client`, `cloudsql.instanceUser`; separate database principal. Migration Job is **not implemented yet**. |
| `meridian-poc-dev1`, `dev2`, `dev3` | Per-human developer identities | No project-wide roles, no Cloud SQL, no secrets. Each real human may impersonate their **own** developer SA only. Job-specific run invocation will be granted when the Job exists. |

### Why six service accounts?

The request has one deployer, one API runtime and three developer SAs. We add a **sixth**, distinct migration runtime SA, to avoid giving developer-trigger identities database DDL access.

### Two Terraform trust zones

1. **Bootstrap**, run by a privileged administrator, creates the GCS state bucket and *all six* SAs and their project-level IAM bindings.
2. **PoC**, run by the deployer SA, creates the application infrastructure and grants resource-level secret and service access. The deployer cannot directly grant itself arbitrary project IAM roles.

The predefined project roles in bootstrap are **not perfect least privilege**: some roles can manage all corresponding resources in the dedicated project. To harden production, replace them with narrowly tailored custom roles and split duties across more projects or deployment identities. Grant `roles/iam.serviceAccountTokenCreator` to the human or CI identity **only on the deployer SA**, out of band during administrator bootstrap, not to the deployer itself. Never generate a JSON key.

### Three developers

The `developer_emails` variable takes an optional mapping, which must be supplied once the human identities are known. Each human can impersonate their own developer SA only. When the migration Job is implemented, grant `roles/run.invoker` **on that specific Job** to each developer SA, not at the project level; do not grant `run.jobs.runWithOverrides`. IAM policy and database SQL grants are distinct.

### Cloud SQL IAM DB login

Cloud SQL for PostgreSQL is configured with `cloudsql.iam_authentication=on`. `google_sql_user.api_iam` registers a `CLOUD_IAM_SERVICE_ACCOUNT` database principal, whose username is the SA email without `.gserviceaccount.com`. The Python Connector uses Application Default Credentials of the Cloud Run runtime SA, `enable_iam_auth=True`, and `IPTypes.PRIVATE` to obtain short-lived tokens. The connector needs egress to Google APIs on TCP 443 and Cloud SQL on TCP 3307. <https://docs.cloud.google.com/sql/docs/postgres/iam-logins>

IAM login proves identity, **not** database privileges. PostgreSQL `GRANT` for tables/schemas must be provisioned separately when the application uses real tables. The exercise's `SELECT 1` probe proves the DB login and query path, not schema privileges.

### Conflict with the exercise's literal wording

The exercise asks for **two secrets: database password and third-party API token**. Both are now implemented and read by the API per request; the password belongs to a separate built-in PostgreSQL user that the API does **not** use for database login. The API continues to use automatic IAM database authentication. The proposed future group `db_secret_reader` is NOT provisioned or granted access yet (requires directory-backed identity and a reviewed IAM binding); it is intended to read only the password secret, while the API SA receives scoped access to both secrets to satisfy the exercise's runtime-read requirement. This is an explicitly documented PoC concession to the exercise, not our preferred production password-handling architecture. See `docs/SECRETS-DESIGN.md`.

### Outstanding verification

- Confirm provider resources and IAM policy scope with `terraform validate` and a plan.
- Verify automatic IAM database login in a deployed instance; verify public IP is disabled.
- Prove runtime has no schema DDL and developers have no direct SQL access.
- Verify Cloud SQL API, Private Google Access and egress routing on live Cloud Run.
- Never claim a migration Job exists or works until implemented and tested.


## Review amendment — 2026-11-11

The bootstrap has a `terraform_operator_email` variable that grants a named human `roles/iam.serviceAccountTokenCreator` only on the deployer SA (not project-wide). The operator must supply their actual account email when bootstrapping; an empty default creates no binding.

We **did not** add a project-wide `roles/iam.serviceAccountViewer`: the deployer already has `roles/iam.serviceAccountUser` directly on the API and migration SAs, and that role includes `iam.serviceAccounts.get`, which is required by the two `data.google_service_account` lookups. This is a more restrictive IAM boundary. Confirm the effective permissions with a live Terraform plan; investigate any missing API/identity role only if observed.


## Commit reviewer — project-wide read-only access (2026-11-11)

Bootstrap grants `roles/viewer` on project `commitask` to the external reviewer `user:gcp-hr@comm-it.cloud` using `google_project_iam_member.commit_reviewer_viewer`. This provides project-wide resource inspection without modification permissions. Basic Viewer does **not** provide `secretmanager.versions.access` (secret values) and does not independently grant `storage.objects.get` on the Terraform state bucket, which contains generated secret payloads. Never grant `roles/secretmanager.secretAccessor` or `roles/storage.objectViewer` merely for interview review.

This is an intended binding in the **privileged bootstrap root**, not yet applied to GCP. Validate its actual existence after `terraform apply`. Read-only inspection may be limited for some services without extra service-specific roles; add only if a demonstrated review need justifies it.


## Security review — 2026-11-11: identities not used yet

The three `dev1/dev2/dev3` service accounts and `migration` service account are **future architecture scaffolding** only. The migration Cloud Run Job is not implemented, no developer SAs have a Job-specific Run Invoker grant, and the migration SA has not been exercised in a runtime. Their presence does not constitute working migrations. To truly enforce minimal privileges while the Job is absent, a later cleanup should defer both the migration identity and its Cloud SQL roles until the migration capability exists, or implement the job and permission boundary fully.

The GitHub PR workflow no longer impersonates the deployer; the full-write WIF binding was removed. A future CI plan SA must have separately reviewed rights and understand that Terraform state currently contains generated password/token values. See `docs/CI-CD.md`.
