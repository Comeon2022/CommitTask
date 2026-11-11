# ADR-004 — One deployment region, EU-resident Terraform state

**Status:** Updated in Terraform source, not yet deployed or validated.  
**Default application region:** `europe-west1` (Belgium).  
**Allowed deployment regions:** `europe-west1` (Belgium), `europe-west3` (Germany), `europe-west4` (Netherlands).  
**Terraform state location:** `EU` multi-region (intentional exception).

## Architecture decision

A *single environment* is deployed to **one** approved EU region at a time. All region-configurable application resources in that environment share the exact `var.region` value. The Terraform state is an infrastructure control-plane artifact, not an application workload; it is deliberately stored in the `EU` multi-region for greater resilience to a regional outage.

| Resource | Placement |
| --- | --- |
| Cloud Run API | `var.region` |
| Cloud SQL PostgreSQL | `var.region` |
| VPC subnet / Direct VPC egress | `var.region` |
| Artifact Registry Docker repository | `var.region` |
| Secret Manager DB-password replica | One user-managed replica in `var.region` |
| Secret Manager API-token replica | One user-managed replica in `var.region` |
| GCS Terraform State bucket | **`EU` multi-region** for cross-region redundancy; exception to one-region rule |

The Terraform roots `terraform/bootstrap` and `terraform/poc` each declare the same allowed-region validation. This duplication is normal for independent Terraform roots and is intentional; update/test **both** together. The GitHub Actions validation job checks Terraform syntax; any policy synchronization needs human review, or future extraction into shared policy tooling.

## Why not hard-code the single region?

`europe-west1` is the default but alternate approved EU regions allow a controlled fresh deployment if business or regulatory constraints change. **Changing `var.region` on an existing deployment is NOT an automatic failover or safe live migration**: locations for some managed services are immutable and resources may be replaced, affecting data and availability. Production expansion should use additional environment/state separation and a data migration/replication plan.

Meridian may serve customers in the US later. **US-based customers do not automatically require US-hosted data**; residency, latency, contractual requirements and US hosting should be reviewed with the customer. This PoC does not approve US region deployment or implement multi-region service delivery.

## Why keep state in EU multi-region?

Cloud Storage `EU` multi-region is EU-resident and provides geographic redundancy. This improves availability of Terraform state after a regional failure while retaining EU geographic storage boundaries. However, replication is **asynchronous** and may not have completed for the latest state object at the time of a failure. GCS object versioning and least-privilege bucket IAM remain required; this is **not a guarantee of zero data loss**, nor does it deliver HA for the zonal database.

Cost and latency of multi-region storage can exceed single-region alternatives; for an evaluation the state volume is small. If a production system requires defined cross-region replication times, evaluate configurable EU dual-region with turbo replication after confirming the residency and cost requirements.

## Global/project-scoped resources

VPC networks, PSA global IP allocations, project IAM/service accounts, Google APIs, and GitHub Workload Identity Federation are global or project-scoped by design. These have no meaningful `var.region` placement; WIF resource identifiers contain `locations/global`.

## Acceptance / test plan

1. Confirm both Terraform roots accept only `europe-west1`, `europe-west3`, or `europe-west4` (and default to `europe-west1`).
2. For a chosen `var.region`, inspect the plan: Cloud Run, Cloud SQL, subnet, Artifact Registry and both Secret Manager replicas must match exactly.
3. Confirm state bucket is `EU`, versioned, private, and uses uniform bucket-level access.
4. Confirm container image references the selected region's Artifact Registry repository; the provided `terraform.tfvars.example` is only a default-region example.
5. Test without altering any deployed infrastructure; a different allowed region requires controlled new deployment/migration planning.
6. Review costs, network access and availability objectives before declaring production readiness.

**Immutability:** Bucket location and secret replication location are not in-place regional switches. Neither Terraform root has been applied to GCP yet; changes are still safe source edits.

References: https://docs.cloud.google.com/storage/docs/locations ; https://docs.cloud.google.com/storage/docs/availability-durability ; https://docs.cloud.google.com/secret-manager/docs/locations
