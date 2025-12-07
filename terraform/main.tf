terraform {
  required_version = ">= 1.5.0, < 1.6.0"
  backend "gcs" {
    prefix = "terraform/fc-versions-github/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.6.0"
    }
    github = {
      source  = "integrations/github"
      version = "5.42.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
  }
}

resource "random_string" "action_wip_random" {
  length  = 4
  special = false
  lower   = true
  upper   = false
  numeric = true
}

provider "google" {
  project = var.gcp_project_id
}

// GITHUB
resource "google_iam_workload_identity_pool" "github_actions_deployment" {
  workload_identity_pool_id = "${var.prefix}gha-fc-versions"
  display_name              = "GHA for ${var.github_repository} FC Versions"
  description               = "OIDC identity pool for build FC versions ${var.github_repository} via GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "gha_identity_pool_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions_deployment.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.prefix}gh-provider"
  display_name                       = "E2B GHA identity pool provider"
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }
  attribute_condition = "assertion.repository == \"${var.github_organization}/${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_storage_bucket_iam_member" "fc_versions_bucket_iam" {
  bucket = var.gcs_bucket_name
  role   = "roles/storage.objectUser"
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions_deployment.name}/attribute.repository/${var.github_organization}/${var.github_repository}"
}

// Github
data "google_secret_manager_secret_version" "github_token" {
  secret = "${var.prefix}github-repo-token"
}

provider "github" {
  owner = var.github_organization
  token = data.google_secret_manager_secret_version.github_token.secret_data
}

resource "github_actions_secret" "workload_identity_provider_secret" {
  repository      = var.github_repository
  secret_name     = "GCP_WORKLOAD_IDENTITY_PROVIDER"
  plaintext_value = "${google_iam_workload_identity_pool.github_actions_deployment.name}/providers/${google_iam_workload_identity_pool_provider.gha_identity_pool_provider.workload_identity_pool_provider_id}"
}

resource "github_actions_secret" "gcp_project" {
  repository      = var.github_repository
  secret_name     = "GCP_PROJECT_ID"
  plaintext_value = var.gcp_project_id
}

resource "github_actions_variable" "gcs_bucket_name" {
  repository    = var.github_repository
  value         = var.gcs_bucket_name
  variable_name = "GCP_BUCKET_NAME"
}
