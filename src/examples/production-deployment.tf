
# Production Deployment Example
# This file demonstrates a complete production-ready Artifactory configuration

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    artifactory = {
      source  = "jfrog/artifactory"
      version = "~> 10.0"
    }
  }

  # Production Terraform Cloud configuration
  cloud {
    organization = "enterprise-corp"
    
    workspaces {
      name = "artifactory-production"
    }
  }
}

# Production-specific local values
locals {
  environment = "production"
  
  # Production repository configuration
  production_repositories = {
    "docker-prod" = {
      description      = "Production Docker images"
      includes_pattern = "**/*"
      excludes_pattern = "*-SNAPSHOT*"
      max_snapshots   = 50
    }
    "npm-prod" = {
      description      = "Production NPM packages"
      includes_pattern = "**/*"
      excludes_pattern = "*-beta*,*-alpha*"
      max_snapshots   = 30
    }
    "maven-prod" = {
      description      = "Production Maven artifacts"
      includes_pattern = "**/*"
      excludes_pattern = "*-SNAPSHOT*"
      max_snapshots   = 100
    }
    "helm-prod" = {
      description      = "Production Helm charts"
      includes_pattern = "**/*"
      excludes_pattern = "*-dev*"
      max_snapshots   = 25
    }
    "generic-prod" = {
      description      = "Production generic artifacts"
      includes_pattern = "**/*"
      excludes_pattern = "temp/**"
      max_snapshots   = 20
    }
  }
  
  # Production service users with specific roles
  production_service_users = {
    "ci-cd-production" = {
      email  = "cicd-prod@enterprise-corp.com"
      groups = ["deployers", "readers"]
    }
    "backup-service" = {
      email  = "backup-prod@enterprise-corp.com"
      groups = ["backup-operators"]
    }
    "monitoring-service" = {
      email  = "monitoring-prod@enterprise-corp.com"
      groups = ["readers", "health-checkers"]
    }
    "security-scanner" = {
      email  = "security-prod@enterprise-corp.com"
      groups = ["scanners", "readers"]
    }
  }
  
  # Production security groups with fine-grained permissions
  production_security_groups = {
    "deployers" = {
      description      = "Production deployment group"
      admin_privileges = false
      realm           = "internal"
      realm_attributes = "department=engineering"
    }
    "backup-operators" = {
      description      = "Backup and recovery operations"
      admin_privileges = false
      realm           = "internal"
      realm_attributes = "department=infrastructure"
    }
    "scanners" = {
      description      = "Security scanning services"
      admin_privileges = false
      realm           = "internal"
      realm_attributes = "department=security"
    }
    "health-checkers" = {
      description      = "System monitoring and health checks"
      admin_privileges = false
      realm           = "internal"
      realm_attributes = "department=operations"
    }
    "readers" = {
      description      = "Read-only access for services"
      admin_privileges = false
      realm           = "internal"
      realm_attributes = "access_level=readonly"
    }
  }
  
  # Production permission targets with strict access controls
  production_permission_targets = {
    "docker-production-deploy" = {
      repositories     = ["docker-prod"]
      includes_pattern = "**/*"
      excludes_pattern = ""
      user            = "ci-cd-production"
      permissions     = ["read", "write", "annotate", "deploy"]
    }
    "npm-production-deploy" = {
      repositories     = ["npm-prod"]
      includes_pattern = "**/*"
      excludes_pattern = ""
      user            = "ci-cd-production"
      permissions     = ["read", "write", "annotate"]
    }
    "backup-access" = {
      repositories     = ["docker-prod", "npm-prod", "maven-prod", "helm-prod", "generic-prod"]
      includes_pattern = "**/*"
      excludes_pattern = ""
      user            = "backup-service"
      permissions     = ["read"]
    }
    "security-scan-access" = {
      repositories     = ["docker-prod", "npm-prod", "maven-prod"]
      includes_pattern = "**/*"
      excludes_pattern = ""
      user            = "security-scanner"
      permissions     = ["read", "annotate"]
    }
  }
  
  # Production service tokens with appropriate expiration
  production_service_tokens = {
    "ci-prod-token" = {
      username    = "ci-cd-production"
      end_date    = "2025-03-31T23:59:59Z"
      refreshable = true
      scope       = "applied-permissions/user"
    }
    "backup-token" = {
      username    = "backup-service"
      end_date    = "2025-06-30T23:59:59Z"
      refreshable = true
      scope       = "applied-permissions/user"
    }
    "monitoring-token" = {
      username    = "monitoring-service"
      end_date    = "2025-12-31T23:59:59Z"
      refreshable = true
      scope       = "applied-permissions/user"
    }
  }
}

# Module call for main Artifactory configuration
module "artifactory_production" {
  source = "../terraform"
  
  # Terraform Cloud settings
  tfc_organization = "enterprise-corp"
  tfc_workspace    = "artifactory-production"
  
  # Environment configuration
  environment  = local.environment
  project_name = "enterprise-artifactory"
  owner        = "platform-engineering"
  
  # Production Artifactory connection
  artifactory_url = "https://enterprise-corp.jfrog.io"
  
  # Enhanced connection settings for production
  request_timeout = 120
  retry_max      = 5
  retry_wait_min = 2
  retry_wait_max = 60
  
  # Production repositories
  repositories = local.production_repositories
  
  # Production service users
  service_users = local.production_service_users
  
  # Production security groups
  security_groups = local.production_security_groups
  
  # Production permission targets
  permission_targets = local.production_permission_targets
  
  # Production service tokens
  service_tokens = local.production_service_tokens
  
  # Token rotation trigger (increment monthly)
  token_rotation_trigger = 202412 # YYYYMM format
  
  # LDAP configuration for enterprise authentication
  enable_ldap              = true
  ldap_user_dn_pattern    = "uid={0},ou=people,dc=enterprise-corp,dc=com"
  ldap_search_filter      = "(uid={0})"
  ldap_search_base        = "ou=people,dc=enterprise-corp,dc=com"
  ldap_auto_create_user   = true
  
  # Production backup configuration
  backup_cron_schedule   = "0 1 * * *" # Daily at 1 AM
  backup_retention_hours = 720         # 30 days
  backup_excluded_repos  = []          # Backup all repos in production
}

# Additional production-specific configurations

# Virtual repositories for production distribution
resource "artifactory_virtual_generic_repository" "docker_virtual_prod" {
  key                            = "docker-virtual-prod"
  description                    = "Virtual repository for production Docker images"
  repositories                   = ["docker-prod", "docker-remote"]
  default_deployment_repo        = "docker-prod"
  includes_pattern              = "**/*"
  excludes_pattern              = ""
  artificial_hierarchy_enabled   = true
}

resource "artifactory_virtual_npm_repository" "npm_virtual_prod" {
  key                     = "npm-virtual-prod"
  description            = "Virtual repository for production NPM packages"
  repositories           = ["npm-prod", "npm-remote"]
  default_deployment_repo = "npm-prod"
  includes_pattern       = "**/*"
  excludes_pattern       = ""
}

# Remote repositories for upstream dependencies
resource "artifactory_remote_docker_repository" "docker_hub_remote" {
  key                         = "docker-remote"
  description                = "Remote repository for Docker Hub"
  url                        = "https://registry-1.docker.io/"
  username                   = ""
  password                   = ""
  repo_layout_ref            = "simple-default"
  hard_fail                  = false
  offline                    = false
  blacked_out               = false
  priority_resolution       = false
  store_artifacts_locally   = true
  socket_timeout_millis     = 15000
  local_address             = ""
  retrieval_cache_period_seconds = 7200
  metadata_retrieval_timeout_seconds = 60
  
  # Security settings
  block_mismatching_mime_types = true
  bypass_head_requests        = false
}

# Replication configuration for disaster recovery
resource "artifactory_push_replication" "production_replication" {
  repo_key                   = "docker-prod"
  cron_exp                  = "0 3 * * *" # Daily at 3 AM
  enable_event_replication  = true
  url                       = "https://enterprise-corp-dr.jfrog.io"
  username                  = "replication-user"
  password                  = var.replication_password
  enabled                   = true
  sync_deletes             = false
  sync_properties          = true
  sync_statistics          = false
  path_prefix              = ""
  
  depends_on = [
    module.artifactory_production
  ]
}

# Cleanup policies for production repositories
resource "artifactory_artifact_cleanup_policy" "production_cleanup" {
  name        = "production-cleanup-policy"
  description = "Cleanup policy for production repositories"
  
  criteria {
    op    = "and"
    criteria {
      op    = "olderThan"
      value = "365d" # Keep artifacts for 1 year
    }
    criteria {
      op    = "unusedSince"
      value = "90d"  # Remove unused artifacts after 90 days
    }
  }
}

# Production monitoring and alerts
resource "artifactory_webhook" "production_alerts" {
  key         = "production-alerts"
  description = "Webhook for production alerts"
  url         = "https://alerts.enterprise-corp.com/webhook"
  secret      = var.webhook_secret
  proxy       = ""
  
  criteria {
    any_local        = false
    any_remote       = false
    any_federated    = false
    repo_keys        = ["docker-prod", "npm-prod", "maven-prod"]
    include_patterns = ["**/*"]
    exclude_patterns = ["temp/**"]
  }
  
  handlers {
    handler    = "repo-events"
    url        = "https://alerts.enterprise-corp.com/repo-events"
    secret     = var.webhook_secret
    proxy      = ""
    http_headers = {
      "X-Environment" = "production"
      "X-Service"     = "artifactory"
    }
  }
}

# Outputs for integration with other systems
output "production_repository_urls" {
  description = "Production repository URLs"
  value = {
    docker = "${module.artifactory_production.artifactory_url}/docker-prod"
    npm    = "${module.artifactory_production.artifactory_url}/npm-prod"
    maven  = "${module.artifactory_production.artifactory_url}/maven-prod"
    helm   = "${module.artifactory_production.artifactory_url}/helm-prod"
  }
}

output "production_virtual_repository_urls" {
  description = "Production virtual repository URLs"
  value = {
    docker = "${module.artifactory_production.artifactory_url}/docker-virtual-prod"
    npm    = "${module.artifactory_production.artifactory_url}/npm-virtual-prod"
  }
}

output "production_service_users" {
  description = "Production service user names"
  value       = keys(local.production_service_users)
}

# Variables for production-specific configuration
variable "replication_password" {
  description = "Password for replication user"
  type        = string
  sensitive   = true
}

variable "webhook_secret" {
  description = "Secret for webhook authentication"
  type        = string
  sensitive   = true
}
