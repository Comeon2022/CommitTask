# Meridian Payments — Google Cloud Evaluation

**Candidate:** Lior Karu | **Project:** `commitask01` | **Region:** `europe-west1`  
**Live Endpoint:** [`https://meridian-poc-api-egkkxtz23a-ew.a.run.app/health`](https://meridian-poc-api-egkkxtz23a-ew.a.run.app/health)  
**Contract Verification:** HTTP 200 OK — `{"candidate": "Lior Karu", "commit": "...", "db": "ok", "region": "europe-west1", "secret": "ok"}`

---

## 1. Architecture & Key Decisions

- **Compute Choice (Cloud Run):** Selected serverless Cloud Run over GKE/GCE. For a single lightweight API evaluation, Cloud Run provides zero-management scaling, built-in TLS, native Direct VPC Egress to private IPs, and minimal idle cost without cluster overhead.
- **Network Isolation:** Rejected the customer's request to use the `default` VPC. Provisioned a custom VPC (`meridian-poc-vpc`), private subnet, and Private Services Access (PSA) peering for Cloud SQL.
- **Database & IAM Authentication:** Cloud SQL for PostgreSQL 16 is strictly internal (`ipv4_enabled = false`). Application connects via Cloud SQL Python Connector using **IAM database authentication** (short-lived OAuth tokens); no database password is hardcoded or used by the app.
- **Secrets Management:** Secret Manager replicates to EU (`europe-west1`) for GDPR data residency. The API reads both the provider token and a built-in DB user password at runtime under its dedicated identity.
- **CI/CD & Zero Long-Lived Credentials:** Rejected storing service account JSON keys in GitHub Secrets. Configured Workload Identity Federation (WIF) with GitHub Actions OIDC:
  - Repository-scoped `meridian-poc-builder` for image pushes.
  - Service-scoped `meridian-poc-ci-deploy` for automated deployment to Cloud Run with live `/health` gate.
  - Read-only `meridian-poc-plan` for manual main plans.

---

## 2. How to Run & Verify

1. **Bootstrap (run once as human administrator):**
   ```powershell
   cd terraform/bootstrap
   terraform init && terraform apply
   ```
2. **Deploy Infrastructure:**
   ```powershell
   cd ../poc
   terraform init -backend-config="bucket=commitask01-tfstate-238671625358" -backend-config="prefix=meridian/poc"
   terraform apply
   ```
3. **CI/CD Pipeline:** Pushing to `main` triggers `.github/workflows/docker-build.yml` followed by `.github/workflows/cloudrun-deploy.yml`, which updates Cloud Run to the immutable image digest and verifies `/health`.
4. **Endpoint Probe:**
   ```bash
   curl -i https://meridian-poc-api-egkkxtz23a-ew.a.run.app/health
   ```

---

## 3. Working With AI & Corrections

- **Tools Used:** ChatGPT (GPT-6) and Antigravity (Claude 3.5 Sonnet / Gemini 1.5 Pro). AI generated ~70% of the initial scaffolding and documentation drafts; all architecture, security boundaries, and debugging were directed by the architect.
- **Three Critical AI Rejections / Corrections (see `AI-LOG.md`):**
  1. **Cloud SQL Edition on PG16 (`AI-LOG.md` Session 2, Item 1):** AI specified `tier = "db-f1-micro"` with PostgreSQL 16 without `edition = "ENTERPRISE"`. PG16 defaults to Enterprise Plus, which rejects shared-core tiers. Corrected in `terraform/poc/data.tf`.
  2. **Privileged PR Plan Security Hole (`AI-LOG.md` Session 2, Item 2):** AI initially generated a GitHub Actions PR plan using the privileged deployer SA. Because PR workflows run untrusted branch code, this could allow arbitrary apply/destruction. Replaced with credential-free PR checks and an isolated, read-only plan identity.
  3. **Silent DB Health Failure in pg8000 (`AI-LOG.md` Session 2, Item 3):** AI implemented `cursor.fetchone() == (1,)`. In runtime testing, `pg8000` returned a list `[1]`, causing `[1] == (1,)` to silently evaluate to `False` (`"db": "error"`). Corrected to validate scalar `row[0] == 1` and properly manage connection close.

---

## 4. Time Spent & With More Time

- **Actual Time Spent:** ~4.5 hours (within the 5-hour hard limit).
- **With More Time:**
  - **Developer Migrations:** Fully implement the designed Cloud Run Job (ADR-001) with execute-only permissions for developers.
  - **Secrets Seeding:** Provision secret values outside Terraform (via KMS/Vault) to avoid storing plaintext passwords in Terraform state.
  - **Production Ingress:** Place Cloud Run behind Cloud Load Balancing with Cloud Armor WAF and DDoS mitigation.
  - **HA & DR:** Configure Cloud SQL High Availability (Regional), Point-In-Time Recovery, and `deletion_protection = true`.
