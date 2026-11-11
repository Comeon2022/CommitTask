# Production Security Gap Assessment — Meridian Payments PoC

**Assessment date:** 2026-11-11  
**Scope:** Google Cloud PoC in project `commitask01`, region `europe-west1`  
**Classification:** A documented gap assessment for a demo, **not** a PCI DSS certification or production security approval.

## Executive summary

The PoC demonstrates an operational Cloud Run API, IAM-authenticated Cloud SQL connectivity, Secret Manager integration, GitHub Actions Build/Deploy with separate Workload Identity Federation identities, and explicit Terraform state-bucket least-privilege IAM. These controls are **not sufficient** for a production payment processing environment.

The following are six material production gaps, in implementation priority order. Statements below distinguish **confirmed PoC observations** from settings that require independent verification.

| # | Gap | Current PoC | Production target | Priority |
| --- | --- | --- | --- | --- |
| 1 | Secrets in Terraform state | Terraform-generated password and synthetic token remain in state | Provision/rotate secrets outside ordinary Terraform state; reduce privileged state readers | Critical |
| 2 | Public API exposure | Cloud Run ingress is `all`, with `allUsers` Invoker | Approved authentication, controlled ingress, HTTPS load balancing, Cloud Armor/WAF and rate limiting | Critical |
| 3 | Unrestricted outbound traffic | Cloud Run egress is `private-ranges-only`; public-bound traffic does not pass through the dedicated VPC path | Route all egress through controlled VPC networking; use Cloud NAT/static IP where needed and enforce effective egress filtering | High |
| 4 | Database transport security | Python Cloud SQL connector uses encrypted connections; server-side SSL enforcement setting has not been independently verified | Enforce verified TLS for permitted direct DB clients and document connector transport policy | High |
| 5 | Auditability and PCI DSS controls | No evidence yet of comprehensive Data Access audit logging and retention policy | Enable relevant Data Access logs, secure routing/retention and review, and map requirements against actual PCI DSS scope | High |
| 6 | Resilience and recovery | Cloud SQL configured as a single-zone PoC without verified HA/recovery objectives | Regional HA, backups/PITR, deletion protection, recovery testing, defined RPO/RTO; consider cross-region DR | High |

## 1. Secrets persisted in Terraform state

**Current state:** Terraform generates a database-password secret and a synthetic third-party token. Even when stored in Secret Manager, values created or managed using ordinary Terraform secret-version resources can also be present in Terraform state and plan outputs. The fact that CLI output marks values sensitive does **not** remove them from state.

**Risk:** An account able to read the state object (including the dedicated read-only Plan SA) may gain access to the PoC secret values. The bucket has been hardened to operator Storage Admin, Deployer Object Admin and Plan Object Viewer, but this does not eliminate state-resident secret exposure.

**Production remediation:**
- Seed real values via an approved secrets lifecycle mechanism, separate from Terraform state; where supported and appropriately tested, consider provider write-only/ephemeral mechanisms.
- Keep Terraform responsible for secret metadata, IAM and references, not the secret payload.
- Define automatic rotation and revocation procedures, restrict secret access by identity, and alert on unusual reads.
- Separate state by trust zone, restrict state readers, and apply retention/backup governance.

**Verification:** Inspect Terraform resources and state exposure pathways without printing secret payloads. Test rotation and access denial.

## 2. Public Cloud Run service exposure

**Confirmed current state:** `meridian-poc-api` is configured with all ingress and `roles/run.invoker` for `allUsers`. The public `/health` endpoint was intentionally accessible for demo validation.

**Risk:** The application is directly reachable without an infrastructure-level authentication boundary. A green health result does not validate payment/API abuse resistance.

**Production remediation:**
- Require application-level authentication and authorization appropriate to the clients and payment workflows.
- Use an external Application Load Balancer with Cloud Armor policy (WAF, rate limiting, DDoS protection, rules based on observed threats, and geo restrictions **where justified**).
- Restrict Cloud Run ingress to `internal-and-cloud-load-balancing` when using the external load balancer; avoid bypass via the default `run.app` endpoint.
- Remove `allUsers` Invoker if the service must be identity-protected rather than publicly reachable through a controlled gateway.
- Do not treat Cloud Armor as a substitute for authorization, input validation or API abuse controls.

**Verification:** Try the default URL directly, test protected route authentication and verify enforcement through the approved endpoint.

## 3. Outbound connectivity and exfiltration controls

**Confirmed current state:** Cloud Run revision egress is `private-ranges-only`. Private-range traffic is routed into the specified VPC; public internet-bound traffic is not uniformly governed by its VPC egress policies.

**Risk:** Lack of centrally enforced destinations and source attribution can enable undesired outbound connections.

**Production remediation:**
- Configure supported Cloud Run Direct VPC egress for `all-traffic` (or another validated VPC egress path).
- Use Cloud NAT with reserved external addresses for predictable outbound IPs and third-party allowlisting, where required.
- **Cloud NAT is not a destination firewall or DLP system:** separately enforce egress policies using suitable firewall/proxy/inspection architecture and monitor destinations.
- Preserve private Cloud SQL connectivity and explicit access to Google APIs; confirm DNS, routing, and Private Google Access/Private Service Connect choices before rollout.

**Verification:** Inspect actual egress routing and logs; test blocked and allowed destinations.

## 4. Database transport encryption and server policy

**Current state:** The Python Cloud SQL connector uses secure authenticated transport. The PoC's Cloud SQL server-side `ssl_mode` enforcement value was **not independently confirmed** in the captured checks. It would be inaccurate to claim that plaintext SQL connections are definitely allowed without inspecting the setting and access method.

**Production remediation:**
- Define and enforce a suitable Cloud SQL PostgreSQL SSL/TLS policy for each supported connection path, including certificate validation for direct clients when applicable.
- Keep Cloud SQL private-only and use IAM database authentication for appropriate workload access.
- Confirm that TLS enforcement is compatible with the connector and migration tooling.
- Test failed non-compliant direct connections, and implement least-privilege PostgreSQL roles and grants.

**Verification:** Inspect Cloud SQL instance SSL configuration and perform an approved connection test.

## 5. Audit logging and PCI DSS evidence

**Current state:** The PoC has not supplied evidence of comprehensive Data Access Audit Logs for Secret Manager, data services, or application-level transaction auditing, nor an immutable retention and review policy. Admin Activity logging alone is insufficient to demonstrate audit coverage for a payment environment.

**Production remediation:**
- Enable relevant Cloud Audit Logs **Data Access** categories as required, noting service-specific defaults and log volume/cost.
- Build application-level audit trails for sensitive operations and data access where infrastructure audit logs cannot identify business-level SQL/transaction actions.
- Route appropriate logs to access-controlled, retention-governed storage; evaluate bucket retention lock where required, and test logging integrity.
- Define ownership for monitoring, incident response and access reviews.
- Scope the actual cardholder data environment and map controls to the applicable **PCI DSS version and assessment requirements**. Do not claim PCI compliance solely from enabling logs.

**Verification:** Generate test read/write events, confirm ingestion, access controls, retention and audit review evidence.

## 6. High availability, backup and disaster recovery

**Current state:** The PoC database was deployed without verified regional HA or production-grade RPO/RTO evidence. The precise current deletion-protection flag and backup/PITR settings should be inspected rather than assumed.

**Production remediation:**
- Configure Cloud SQL **regional high availability across zones within a region** for zonal failure resilience. Different zones are not equivalent to independent geographic regions.
- Enable appropriate deletion protection, automated backups and point-in-time recovery.
- Define explicit Recovery Point Objective (RPO) and Recovery Time Objective (RTO) and perform restore/failover drills.
- Consider cross-region disaster recovery if the business requirements demand surviving region-wide outages.
- Design application retries, connection pooling and downstream outage behavior for failover.

**Verification:** Review instance settings and run controlled failover/restore tests.

## Additional production gaps and open checks

1. **Identity governance:** Scope permissions further with custom roles if warranted. Confirm unused default Compute Engine SA no longer has `roles/editor`, and confirm the temporary project-wide `roles/storage.admin` recovery grant has been removed after bucket-scoped access was verified.
2. **GitHub protection:** The active `protect main` Ruleset originally matched `~ALL` branches, not just `main`. Scope it to main to preserve feature-branch workflow. The zero-reviewer PR setting does not provide a second-person review. Consider required checks and stronger protections for workflows.
3. **CI supply chain:** Add vulnerability scanning, verified provenance/signatures, image update policy, dependency monitoring and release rollback procedures.
4. **Monitoring and operations:** Alerts, SLOs, incident runbooks, secret rotation rehearsals and cost controls.
5. **Application security:** Threat modeling, secure payment provider integration, tokenization/minimization, idempotency, rate limits, abuse monitoring, and penetration testing. Avoid processing real cardholder data until controls and assessment scope are defined.
6. **Incomplete capabilities:** Developer-triggered migration job, production database schema grants and real end-to-end payment processing are not implemented in this PoC.

## Acceptance criteria for a production promotion

This PoC must **not** be declared production-ready until each priority risk above has an assigned owner, implemented control, evidence of successful testing, and sign-off under the organization's security and PCI compliance processes.

**Related documents:** [README](../README.md), [IAM design](IAM-DESIGN.md), [CI/CD design](CI-CD.md), [Secrets design](SECRETS-DESIGN.md).
