resource "google_storage_bucket_iam_member" "terraform_operator_bucket_admin" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.admin"
  member = "user:karu.lior@gmail.com"
}