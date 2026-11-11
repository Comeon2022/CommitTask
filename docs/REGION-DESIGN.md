# ADR-004 — Single-region placement

**Status:** Implemented in Terraform source, not yet deployed or validated.  
**Chosen region:** `europe-west1` (Belgium).

## Decision

All **regional** infrastructure and region-configurable data replicas use **one region**, `europe-west1`:

| Resource | Placement |
| --- | --- |
| Cloud Run API | `var.region` |
| Cloud SQL PostgreSQL | `var.region` |
| VPC subnet / Direct VPC egress | `var.region` |
| Artifact Registry Docker repository | `var.region` |
| Secret Manager DB password secret replica | `var.region` (user-managed, single replica) |
| Secret Manager external API token replica | `var.region` (user-managed, single replica) |
| GCS Terraform State bucket | `var.region` (single-region bucket rather than EU multi-region) |

Both Terraform roots (`terraform/bootstrap` and `terraform/poc`) default to `europe-west1` and validate that no other region is passed. The project is assumed to be a disposable, EU-hosted evaluation.

## Resources that cannot be regional

Some Google Cloud control-plane resources are **global or project-scoped by design** and cannot be forced into a regional location:

- VPC network, service networking connection, and private-services-access reserved global address
- Service accounts and project IAM / API enablement
- Workload Identity Pool / Provider (its resource name necessarily contains `locations/global`)
- Global aspects of Secret Manager management (the **payload replicas**, not secret identifiers, are restricted to `europe-west1`)

These are not deployed to another regional location; they simply do not support a regional placement field.

## Important caveat

Single-region placement is not a promise that every Google-managed system or metadata path remains within Belgium. Data processing/storage residency and compliance require a separate analysis. A single region is also a deliberate availability compromise; cross-region disaster recovery would require customer approval and a new decision.

**Immutability warning:** GCS bucket location and Secret Manager replication configurations cannot generally be changed in place. If already deployed elsewhere, a migration and new resource names may be required.

## Acceptance

Before deployment, verify `terraform plan` shows the Cloud SQL instance, Cloud Run service, subnet, Artifact Registry, secrets' replicas, and state bucket all in `europe-west1`. Confirm runtime container image references `europe-west1-docker.pkg.dev` and no regional resource points elsewhere.
