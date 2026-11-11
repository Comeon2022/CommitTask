# ADR-001: Developer-Initiated Schema Migrations

**Status:** Proposed pending customer confirmation  
**Date:** 2026-11-11  
**Decision:** Option C — developer-triggered Cloud Run Job.

## Requirement and unresolved ambiguity

Meridian needs developers to be able to run schema migrations "from their laptops" while PostgreSQL is never reachable from the internet. We interpret the developer's laptop as the **place from which a migration is initiated**, not necessarily where its code executes. This is **not confirmed** by the customer, and does **not** meet a strict requirement for direct laptop-to-database connectivity.

## Proposed workflow

1. Migration scripts are version-controlled, peer-reviewed, and approved in GitHub.
2. CI builds a versioned, immutable migration container; the selected image digest is deployed as a Cloud Run Job.
3. An authorized developer triggers the **already-configured** job through a restricted workflow or `gcloud run jobs execute`.
4. The job authenticates under its dedicated service account, retrieves its own database credential from Secret Manager, and connects to Cloud SQL over private network connectivity through Direct VPC egress.
5. The job applies pending, version-tracked migrations, records its result, and exits. CI makes execution status and logs available without revealing secrets.

```text
Developer laptop
  -> authenticated GitHub workflow / gcloud run jobs execute
  -> Cloud Run Job (approved container image + dedicated IAM identity)
       -> Secret Manager (migration credential)
       -> Direct VPC egress -> custom VPC -> Cloud SQL PostgreSQL (private IP)
```

## Security boundaries

- **Cloud SQL:** no public IP, no authorized public networks.
- **API runtime identity:** least privilege; no migration DDL privileges.
- **Migration job identity:** distinct service account, access only to its required secrets and network/database connectivity.
- **Database identities:** application role has minimum DML; migration role has scoped schema DDL, without PostgreSQL superuser permissions by default.
- **Triggering identity:** can execute only an approved job; cannot update its image, environment variables, service account, or secret bindings.
- **CI/CD identity:** GitHub OIDC + Workload Identity Federation; no long-lived service account JSON key.
- **Audit:** record who requested the run, the reviewed migration/image version, target environment, execution result and timestamps. Avoid secret or sensitive-data logging.
- **Operational safety:** ensure migrations are versioned and not executed concurrently; assess backwards-compatible changes, locking, backups and rollback/roll-forward procedures before production.

## Tradeoffs

**Advantages:** no laptop-to-database route; centralized identity, execution, and audit; close to the eventual production process.

**Costs:** additional job definition, container, permissions, and workflow; developers cannot run arbitrary local migration scripts against the remote database.

**Alternative if rejected:** design an approved private network path (such as corporate VPN) to Cloud SQL with strong user identity, least privilege, and auditing. Cloud SQL Auth Proxy alone does **not** provide the underlying private network route to a private-IP-only instance.

## PoC acceptance checks

1. Cloud SQL has no public address.
2. A developer with execute-only permission can trigger the approved job.
3. An unauthorized identity cannot execute or modify the job.
4. A migration genuinely runs and its version is recorded in PostgreSQL.
5. Application runtime identity cannot change schema.
6. Neither SQL credentials nor provider tokens appear in logs, git history, or Terraform state.
7. All resources are provisioned by Terraform; if any item is intentionally left as a documented design due to the five-hour limit, flag it in README rather than claiming it was deployed.

## Scope and approval

For this exercise, the main health contract and core Terraform slice take priority. The migration job is a **proposed extension**, not a task completion claim until implemented and demonstrated. Ask Meridian explicitly whether remote execution initiated from laptops is acceptable, and in which environments it is allowed.

See `CLARIFICATIONS.md` (developer migrations) and `ASSUMPTIONS.md` (developer access decision).
