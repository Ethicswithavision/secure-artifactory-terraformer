
# Terraform Artifactory Provider Configuration
# Enterprise Security Implementation with TfCB Agent-based Execution

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    artifactory = {
      source  = "jfrog/artifactory"
      version = "~> 10.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.51"
    }
  }

  # Terraform Cloud Configuration
  cloud {
    organization = var.tfc_organization
    
    workspaces {
      name = var.tfc_workspace
    }
  }
}

# Data source for sensitive variables from Terraform Cloud
data "tfe_workspace" "current" {
  name         = var.tfc_workspace
  organization = var.tfc_organization
}

# Artifactory Provider Configuration with Security Hardening
provider "artifactory" {
  url          = var.artifactory_url
  access_token = var.artifactory_access_token
  
  # Security configurations
  check_license = true
  
  # HTTP client configurations for security
  client_cert_path = var.client_cert_path
  client_cert_key  = var.client_cert_key
  
  # Connection security settings
  request_timeout   = var.request_timeout
  retry_max        = var.retry_max
  retry_wait_min   = var.retry_wait_min
  retry_wait_max   = var.retry_wait_max
  
  # Disable insecure connections
  check_license = true
}

# Local values for configuration management
locals {
  # Environment-specific configurations
  environment = var.environment
  
  # Common tags for resources
  common_tags = {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "Terraform"
    Owner         = var.owner
    SecurityLevel = "High"
    Compliance    = "SOC2"
  }
  
  # Security policies
  security_policies = {
    password_policy = {
      min_length    = 12
      require_upper = true
      require_lower = true
      require_digit = true
      require_symbol = true
    }
    
    token_expiry = {
      access_token_ttl  = "24h"
      refresh_token_ttl = "168h" # 7 days
    }
  }
}

# Repository configurations with security settings
resource "artifactory_local_generic_repository" "secure_repo" {
  for_each = var.repositories
  
  key         = each.key
  description = each.value.description
  
  # Security configurations
  includes_pattern = each.value.includes_pattern
  excludes_pattern = each.value.excludes_pattern
  
  # Access control
  repo_layout_ref = "simple-default"
  
  # Audit and compliance
  properties_sets = ["artifactory"]
  
  # Backup and retention
  max_unique_snapshots = each.value.max_snapshots
  
  depends_on = [
    artifactory_user.service_users
  ]
}

# Service users with minimal permissions
resource "artifactory_user" "service_users" {
  for_each = var.service_users
  
  name     = each.key
  email    = each.value.email
  password = var.service_user_passwords[each.key]
  
  # Security settings
  admin                     = false
  profile_updatable         = false
  disable_ui_access        = true
  internal_password_disabled = false
  
  # Groups assignment
  groups = each.value.groups
}

# Permission targets for fine-grained access control
resource "artifactory_permission_target" "repository_permissions" {
  for_each = var.permission_targets
  
  name = each.key
  
  repo {
    repositories         = each.value.repositories
    includes_pattern     = each.value.includes_pattern
    excludes_pattern     = each.value.excludes_pattern
    actions {
      users {
        name        = each.value.user
        permissions = each.value.permissions
      }
    }
  }
}

# Access tokens for service authentication
resource "artifactory_access_token" "service_tokens" {
  for_each = var.service_tokens
  
  username    = each.value.username
  end_date    = each.value.end_date
  refreshable = each.value.refreshable
  
  # Scope limitations for security
  scope = each.value.scope
  
  lifecycle {
    # Prevent accidental token deletion
    prevent_destroy = true
    
    # Rotate tokens regularly
    replace_triggered_by = [
      var.token_rotation_trigger
    ]
  }
}

# Security groups with role-based access
resource "artifactory_group" "security_groups" {
  for_each = var.security_groups
  
  name               = each.key
  description        = each.value.description
  auto_join          = false
  admin_privileges   = each.value.admin_privileges
  realm              = each.value.realm
  realm_attributes   = each.value.realm_attributes
}

# LDAP configuration for enterprise authentication
resource "artifactory_ldap_setting" "enterprise_ldap" {
  count = var.enable_ldap ? 1 : 0
  
  key                   = "ldap_config"
  enabled               = true
  ldap_url              = var.ldap_url
  user_dn_pattern       = var.ldap_user_dn_pattern
  search_filter         = var.ldap_search_filter
  search_base           = var.ldap_search_base
  search_sub_tree       = true
  manager_dn            = var.ldap_manager_dn
  manager_password      = var.ldap_manager_password
  auto_create_user      = var.ldap_auto_create_user
  email_attribute       = "mail"
  
  # Security settings
  allow_user_to_access_profile = false
  paging_support_enabled       = true
}

# Backup configuration for disaster recovery
resource "artifactory_backup" "daily_backup" {
  key                    = "daily-backup"
  enabled                = true
  cron_exp              = var.backup_cron_schedule
  retention_period_hours = var.backup_retention_hours
  excluded_repositories  = var.backup_excluded_repos
  create_archive         = true
  exclude_builds         = false
  send_mail_on_error     = true
}

# System configuration for security hardening
resource "artifactory_general_security" "security_config" {
  enable_anonymous_access = false
  
  # Password policies
  password_settings {
    encryption_policy                 = "REQUIRED"
    expiration_policy_enabled         = true
    expiration_policy_password_max_age = 90
    reset_policy_enabled              = true
    reset_policy_max_attempts         = 3
    reset_policy_time_difference      = "24h"
  }
}

# Outputs for integration with other systems
output "artifactory_url" {
  description = "Artifactory instance URL"
  value       = var.artifactory_url
  sensitive   = false
}

output "repository_urls" {
  description = "Repository URLs for applications"
  value = {
    for k, v in artifactory_local_generic_repository.secure_repo : 
    k => "${var.artifactory_url}/${k}"
  }
  sensitive = false
}

output "service_user_names" {
  description = "Created service user names"
  value       = keys(artifactory_user.service_users)
  sensitive   = false
}

# Health check for monitoring
data "artifactory_system_info" "health" {}

output "system_health" {
  description = "Artifactory system health information"
  value = {
    version     = data.artifactory_system_info.health.version
    revision    = data.artifactory_system_info.health.revision
    license     = data.artifactory_system_info.health.license_hash
    build_time  = data.artifactory_system_info.health.build_number
  }
  sensitive = false
}
