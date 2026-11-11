**To:** Meridian Payments — Platform Lead  
**Subject:** Google Cloud evaluation — clarifications and proposed adjustments before implementation

Hi,

Thanks for the brief. We can deliver a small, working slice that demonstrates the intended application-to-database pattern. Before implementation, I want to confirm a few points and flag two design choices I would not recommend carrying into a production target.

**Evaluation scope and acceptance.** What would make the three-week evaluation successful beyond a working API and PostgreSQL connection? Should we demonstrate deployment repeatability, developer access, security controls, or a particular level of availability and performance? Is there an existing API container or contract we should reuse, or is a minimal representative service acceptable?

**Network isolation.** I agree that PostgreSQL must have no public endpoint. However, private connectivity does not require us to use the *default* VPC. I recommend a dedicated, explicitly configured network instead, to avoid inheriting default rules and to make the production boundary clear. Are there existing CIDR ranges, connectivity requirements, or organizational networking standards we must accommodate?

**Developer migrations.** When you say developers must run schema migrations from laptops, do they need a direct database connection, or is triggering an authenticated migration job/pipeline from their laptops acceptable? If direct access is mandatory, what approved private connectivity (for example, VPN) and developer identity controls are in place? I would not expose PostgreSQL publicly to satisfy this requirement.

**CI identity.** I would not deploy a long-lived service-account JSON key into GitHub Secrets. I recommend GitHub OIDC with Google Cloud Workload Identity Federation and tightly scoped permissions instead. Can the platform team approve that change, and who owns the GitHub repository and GCP IAM configuration?

**Data handling and geography.** Will the evaluation use synthetic data only? Do any cardholder data, personal data, or third-party tokens fall within PCI DSS, GDPR, contractual residency, or audit requirements? Is an EU region acceptable for the evaluation, and does the potential US expansion imply US data residency or only US-based users?

**API exposure and secrets.** Is the public endpoint intended only for health checks, or should application endpoints also be internet-facing? What authentication is expected for the API? Who provisions and rotates the database credential and provider token, and should the evaluation make any real calls to the third-party provider?

**Production expectations.** What are the target availability, backup/restore objectives (RPO/RTO), expected traffic, and budget constraints? I suggest we identify production controls in the design while implementing only the minimum necessary to validate the pattern within the evaluation scope.

Unless you advise otherwise, I will document any unanswered items as explicit assumptions, including their risks and the decisions made to keep the evaluation moving.

Best regards,
[Your Name]