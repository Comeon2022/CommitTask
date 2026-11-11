terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {}
}

variable "project_id" {
  type        = string
  description = "Existing GCP project with billing enabled."
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "subnet_cidr" {
  type    = string
  default = "10.42.0.0/24"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  required_apis = toset([
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each           = local.required_apis
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "app" {
  name                    = "meridian-poc-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.required]
}

resource "google_compute_subnetwork" "app" {
  name                     = "meridian-poc-subnet"
  region                   = var.region
  network                  = google_compute_network.app.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_global_address" "sql_peering" {
  name          = "meridian-poc-sql-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.app.id
}

resource "google_service_networking_connection" "sql" {
  network                 = google_compute_network.app.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.sql_peering.name]
  depends_on              = [google_project_service.required]
}

output "network_id" {
  value = google_compute_network.app.id
}

output "subnetwork_id" {
  value = google_compute_subnetwork.app.id
}
