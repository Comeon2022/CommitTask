# Meridian Payments PoC — security hardening, managed by Terraform only.
# Applies in the privileged bootstrap root, not the PoC deployer root.

# Enforce zero members on the four legacy convenience roles, so project
# viewers/editors cannot read the Terraform state bucket through inherited
# projectViewer/projectEditor convenience values.
resource "google_storage_bucket_iam_binding" "state_remove_legacy_access" {
  for_each = toset([
    "roles/storage.legacyBucketOwner",
    "roles/storage.legacyBucketReader",
    "roles/storage.legacyObjectOwner",
    "roles/storage.legacyObjectReader",
  ])

  bucket  = google_storage_bucket.terraform_state.name
  role    = each.value
  members = []
}

# There are no intentionally authorized project Editors in this PoC.
# The only reported editor member was the unused Compute Engine default SA.
# Role-wide authoritative binding intentionally keeps roles/editor empty.
resource "google_project_iam_binding" "remove_default_editor" {
  project = var.project_id
  role    = "roles/editor"
  members = []
}
