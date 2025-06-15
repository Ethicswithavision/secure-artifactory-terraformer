
# Variable Definitions for Secure Artifactory Configuration
# All sensitive variables should be set in Terraform Cloud workspace with sensitive flag

# Terraform Cloud Configuration
variable "tfc_organization" {
  description = "Terraform Cloud organization name"
  type        = string
  validation {
    condition     = length(var.tfc_organization) > 0
    error_message = "TfC organization name cannot be empty."
  }
}

variable "tfc_workspace" {
  description = "Terraform Cloud workspace name"
  type        = string
  validation {
    condition     = length(var.tfc_workspace) > 0
    error_message = "TfC workspace name cannot be empty."
  }
}

# Artifactory Connection Variables (Sensitive)
variable "artifactory_url" {
  description = "Artifactory instance URL (HTTPS only)"
  type        = string
  validation {
    condition     = can(regex("^https://", var.artifactory_url))
    error_message = "Artifactory URL must use HTTPS protocol."
  }
}

variable "artifactory_access_token" {
  description = "Artifactory access token (Sensitive - Set in TfC workspace)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.artifactory_access_token) >= 32
    error_message = "Access token must be at least 32 characters long."
  }
}

# SSL/TLS Certificate Configuration
variable "client_cert_path" {
  description = "Path to client certificate for mTLS authentication"
  type        = string
  default     = ""
}

variable "client_cert_key" {
  description = "Path to client certificate private key"
  type        = string
  default     = ""
  sensitive   = true
}

# Connection Configuration
variable "request_timeout" {
  description = "HTTP request timeout in seconds"
  type        = number
  default     = 30
  validation {
    condition     = var.request_timeout > 0 && var.request_timeout <= 300
    error_message = "Request timeout must be between 1 and 300 seconds."
  }
}

variable "retry_max" {
  description = "Maximum number of retry attempts"
  type        = number
  default     = 3
  validation {
    condition     = var.retry_max >= 0 && var.retry_max <= 10
    error_message = "Retry max must be between 0 and 10."
  }
}

variable "retry_wait_min" {
  description = "Minimum wait time between retries in seconds"
  type        = number
  default     = 1
}

variable "retry_wait_max" {
  description = "Maximum wait time between retries in seconds"
  type        = number
  default     = 30
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stage, prod."
  }
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
}

# Repository Configuration
variable "repositories" {
  description = "Map of repositories to create"
  type = map(object({
    description       = string
    includes_pattern  = string
    excludes_pattern  = string
    max_snapshots    = number
  }))
  default = {}
}

# Service Users Configuration
variable "service_users" {
  description = "Map of service users to create"
  type = map(object({
    email  = string
    groups = list(string)
  }))
  default = {}
}

variable "service_user_passwords" {
  description = "Map of service user passwords (Sensitive - Set in TfC workspace)"
  type        = map(string)
  sensitive   = true
  default     = {}
}

# Permission Targets
variable "permission_targets" {
  description = "Map of permission targets for access control"
  type = map(object({
    repositories      = list(string)
    includes_pattern  = string
    excludes_pattern  = string
    user             = string
    permissions      = list(string)
  }))
  default = {}
}

# Service Tokens Configuration
variable "service_tokens" {
  description = "Map of service tokens to create"
  type = map(object({
    username     = string
    end_date     = string
    refreshable  = bool
    scope        = string
  }))
  default = {}
}

variable "token_rotation_trigger" {
  description = "Trigger for token rotation (increment to rotate all tokens)"
  type        = number
  default     = 1
}

# Security Groups
variable "security_groups" {
  description = "Map of security groups to create"
  type = map(object({
    description      = string
    admin_privileges = bool
    realm           = string
    realm_attributes = string
  }))
  default = {}
}

# LDAP Configuration
variable "enable_ldap" {
  description = "Enable LDAP authentication"
  type        = bool
  default     = false
}

variable "ldap_url" {
  description = "LDAP server URL"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ldap_user_dn_pattern" {
  description = "LDAP user DN pattern"
  type        = string
  default     = ""
}

variable "ldap_search_filter" {
  description = "LDAP search filter"
  type        = string
  default     = ""
}

variable "ldap_search_base" {
  description = "LDAP search base"
  type        = string
  default     = ""
}

variable "ldap_manager_dn" {
  description = "LDAP manager DN"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ldap_manager_password" {
  description = "LDAP manager password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ldap_auto_create_user" {
  description = "Auto create LDAP users"
  type        = bool
  default     = true
}

# Backup Configuration
variable "backup_cron_schedule" {
  description = "Cron schedule for backups"
  type        = string
  default     = "0 2 * * *" # Daily at 2 AM
}

variable "backup_retention_hours" {
  description = "Backup retention period in hours"
  type        = number
  default     = 168 # 7 days
}

variable "backup_excluded_repos" {
  description = "List of repositories to exclude from backup"
  type        = list(string)
  default     = []
}
