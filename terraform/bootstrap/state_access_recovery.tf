# Permanent: bootstrap operator can manage the dedicated Terraform state bucket IAM.
# Unlike project-level storage.admin, this grant is scoped to the state bucket.
# This prevents operator lockout when legacy convenience IAM grants are removed.
resource "google_storage_bucket_iam_member" "terraform_operator_bucket_admin" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.admin"
  member = "user:karu.lior@gmail.com"
}
