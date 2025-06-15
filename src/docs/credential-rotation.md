
# Credential Rotation Strategy for Artifactory Terraform Configuration

## Overview
This document outlines the credential rotation strategy for maintaining security in the Artifactory Terraform configuration. Regular credential rotation is essential for maintaining a strong security posture and meeting compliance requirements.

## Rotation Schedule

### Weekly Rotations
- **Service Account Passwords**: Rotate every 7 days
- **Access Tokens**: Rotate short-lived tokens (< 30 days)
- **Agent Pool Tokens**: Rotate on security incidents

### Monthly Rotations  
- **LDAP Service Account**: Rotate monthly
- **Long-lived Access Tokens**: Rotate tokens with 30+ day expiry
- **SSL/TLS Certificates**: Check expiry and rotate if needed

### Quarterly Rotations
- **Master Admin Credentials**: Rotate every 90 days
- **Backup Encryption Keys**: Rotate encryption keys
- **SSH Keys**: Rotate service SSH keys

## Automated Rotation Process

### Prerequisites
1. HashiCorp Vault or AWS Secrets Manager integration
2. Terraform Cloud API access
3. Monitoring and alerting system
4. Rollback procedures documented

### Rotation Workflow

#### 1. Pre-Rotation Validation
```bash
# Verify current credentials work
terraform plan -var="token_rotation_trigger=$(($(date +%s) / 86400))"

# Check system health
curl -H "Authorization: Bearer $CURRENT_TOKEN" \
     https://your-artifactory.jfrog.io/artifactory/api/system/ping
```

#### 2. Generate New Credentials
```bash
# Example: Generate new access token via API
NEW_TOKEN=$(curl -X POST \
  -H "Authorization: Bearer $CURRENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "service-user",
    "expires_in": 604800,
    "refreshable": true,
    "scope": "applied-permissions/user"
  }' \
  https://your-artifactory.jfrog.io/access/api/v1/tokens | jq -r '.access_token')
```

#### 3. Update Terraform Cloud Variables
```bash
# Update sensitive variable in Terraform Cloud
tfe_variable_update() {
  local workspace_id=$1
  local key=$2
  local value=$3
  
  curl -X PATCH \
    -H "Authorization: Bearer $TFE_TOKEN" \
    -H "Content-Type: application/vnd.api+json" \
    -d "{
      \"data\": {
        \"type\": \"vars\",
        \"attributes\": {
          \"key\": \"$key\",
          \"value\": \"$value\",
          \"sensitive\": true,
          \"category\": \"terraform\"
        }
      }
    }" \
    "https://app.terraform.io/api/v2/workspaces/$workspace_id/vars/$key"
}

# Update the access token
tfe_variable_update "$WORKSPACE_ID" "artifactory_access_token" "$NEW_TOKEN"
```

#### 4. Trigger Terraform Apply
```bash
# Increment rotation trigger and apply
terraform apply -var="token_rotation_trigger=$(($(date +%s) / 86400))" -auto-approve
```

#### 5. Validate New Credentials
```bash
# Test new credentials
curl -H "Authorization: Bearer $NEW_TOKEN" \
     https://your-artifactory.jfrog.io/artifactory/api/system/version

# Verify all services are working
terraform plan
```

#### 6. Revoke Old Credentials
```bash
# Revoke the old token
curl -X DELETE \
  -H "Authorization: Bearer $NEW_TOKEN" \
  https://your-artifactory.jfrog.io/access/api/v1/tokens/$OLD_TOKEN_ID
```

## External Secret Management Integration

### AWS Secrets Manager Integration
```hcl
# Example integration with AWS Secrets Manager
data "aws_secretsmanager_secret_version" "artifactory_token" {
  secret_id = "prod/artifactory/access-token"
}

locals {
  artifactory_credentials = jsondecode(data.aws_secretsmanager_secret_version.artifactory_token.secret_string)
}

provider "artifactory" {
  url          = var.artifactory_url
  access_token = local.artifactory_credentials.access_token
}
```

### HashiCorp Vault Integration
```hcl
# Example integration with HashiCorp Vault
data "vault_generic_secret" "artifactory" {
  path = "secret/artifactory/prod"
}

provider "artifactory" {
  url          = var.artifactory_url
  access_token = data.vault_generic_secret.artifactory.data["access_token"]
}
```

### Azure Key Vault Integration
```hcl
# Example integration with Azure Key Vault
data "azurerm_key_vault_secret" "artifactory_token" {
  name         = "artifactory-access-token"
  key_vault_id = var.key_vault_id
}

provider "artifactory" {
  url          = var.artifactory_url
  access_token = data.azurerm_key_vault_secret.artifactory_token.value
}
```

## Monitoring and Alerting

### Key Metrics to Monitor
- Token expiration dates
- Failed authentication attempts
- Rotation job success/failure
- Service availability during rotation
- Time to complete rotation process

### Alert Conditions
- Token expires within 7 days
- Rotation job fails
- Authentication failures spike
- Service downtime during rotation
- Manual intervention required

### Sample Monitoring Script
```bash
#!/bin/bash
# Monitor token expiration

check_token_expiry() {
  local token=$1
  local warning_days=7
  
  # Decode JWT token (simplified - use proper JWT library in production)
  local exp=$(echo $token | cut -d'.' -f2 | base64 -d | jq -r '.exp')
  local current=$(date +%s)
  local days_until_expiry=$(((exp - current) / 86400))
  
  if [ $days_until_expiry -le $warning_days ]; then
    echo "WARNING: Token expires in $days_until_expiry days"
    # Send alert to monitoring system
    curl -X POST \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"Artifactory token expires in $days_until_expiry days\"}" \
      $SLACK_WEBHOOK_URL
  fi
}
```

## Rollback Procedures

### Emergency Rollback
If rotation fails and services are impacted:

1. **Immediate Response**
   ```bash
   # Revert to previous known good token
   tfe_variable_update "$WORKSPACE_ID" "artifactory_access_token" "$PREVIOUS_TOKEN"
   terraform apply -auto-approve
   ```

2. **Service Validation**
   ```bash
   # Verify services are restored
   curl -H "Authorization: Bearer $PREVIOUS_TOKEN" \
        https://your-artifactory.jfrog.io/artifactory/api/system/ping
   ```

3. **Root Cause Analysis**
   - Review rotation logs
   - Check API response codes
   - Validate permission settings
   - Document lessons learned

### Planned Rollback
For scheduled maintenance or testing:

1. Create backup of current state
2. Document rollback steps
3. Schedule maintenance window
4. Execute rollback with monitoring
5. Validate all services post-rollback

## Compliance and Auditing

### Audit Trail Requirements
- All credential changes logged
- Approval workflow for production changes
- Regular audit of access permissions
- Compliance reporting automated

### Documentation Requirements
- Rotation procedures updated
- Emergency contacts maintained
- Service dependencies documented
- Recovery time objectives defined

### Compliance Frameworks
- **SOC 2**: Credential lifecycle management
- **PCI DSS**: Regular password changes
- **ISO 27001**: Access control procedures
- **NIST**: Identity and access management
