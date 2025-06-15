
# Terraform Cloud Agent Pool Configuration
# For secure execution in private networks

terraform {
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.51"
    }
  }
}

# Agent Pool for Artifactory Operations
resource "tfe_agent_pool" "artifactory_agents" {
  name         = "${var.project_name}-artifactory-agents"
  organization = var.tfc_organization
}

# Agent Token for Pool Authentication
resource "tfe_agent_token" "artifactory_agent_token" {
  agent_pool_id = tfe_agent_pool.artifactory_agents.id
  description   = "Token for Artifactory agent pool"
}

# Workspace Assignment to Agent Pool  
resource "tfe_workspace_settings" "artifactory_workspace" {
  workspace_id   = data.tfe_workspace.artifactory.id
  execution_mode = "agent"
  agent_pool_id  = tfe_agent_pool.artifactory_agents.id
}

# Data source for workspace
data "tfe_workspace" "artifactory" {
  name         = var.tfc_workspace
  organization = var.tfc_organization
}

# Variables for secure credential injection
resource "tfe_variable" "artifactory_token" {
  key          = "artifactory_access_token"
  value        = var.artifactory_access_token
  category     = "terraform"
  workspace_id = data.tfe_workspace.artifactory.id
  description  = "Artifactory access token"
  sensitive    = true
}

resource "tfe_variable" "service_passwords" {
  for_each = var.service_user_passwords
  
  key          = "service_user_passwords[\"${each.key}\"]"
  value        = each.value
  category     = "terraform"
  workspace_id = data.tfe_workspace.artifactory.id
  description  = "Service user password for ${each.key}"
  sensitive    = true
}

# LDAP credentials (if LDAP is enabled)
resource "tfe_variable" "ldap_manager_password" {
  count = var.enable_ldap ? 1 : 0
  
  key          = "ldap_manager_password" 
  value        = var.ldap_manager_password
  category     = "terraform"
  workspace_id = data.tfe_workspace.artifactory.id
  description  = "LDAP manager password"
  sensitive    = true
}

# Environment variables for agent runtime
resource "tfe_variable" "agent_env_vars" {
  for_each = {
    "TF_LOG"                    = "INFO"
    "TF_LOG_PATH"              = "/tmp/terraform.log"
    "HTTP_PROXY"               = var.http_proxy
    "HTTPS_PROXY"              = var.https_proxy
    "NO_PROXY"                 = var.no_proxy
    "ARTIFACTORY_LOG_LEVEL"    = "WARN"
    "SSL_CERT_PATH"            = "/etc/ssl/certs"
  }
  
  key          = each.key
  value        = each.value  
  category     = "env"
  workspace_id = data.tfe_workspace.artifactory.id
  description  = "Environment variable for agent execution"
  sensitive    = contains(["HTTP_PROXY", "HTTPS_PROXY"], each.key)
}

# Agent pool outputs
output "agent_pool_id" {
  description = "Agent pool ID for Artifactory operations"
  value       = tfe_agent_pool.artifactory_agents.id
}

output "agent_token" {
  description = "Agent token for pool authentication"
  value       = tfe_agent_token.artifactory_agent_token.token
  sensitive   = true
}

# Variables for agent configuration
variable "http_proxy" {
  description = "HTTP proxy for agent connections"
  type        = string
  default     = ""
}

variable "https_proxy" {
  description = "HTTPS proxy for agent connections"
  type        = string  
  default     = ""
}

variable "no_proxy" {
  description = "No proxy exception list"
  type        = string
  default     = "localhost,127.0.0.1"
}
