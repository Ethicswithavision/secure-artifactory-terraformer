
#!/bin/bash
# Production Deployment Script for Artifactory Terraform Configuration
# This script handles secure deployment with credential validation and rollback capabilities

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/artifactory-deploy-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/tmp/terraform-backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("terraform" "curl" "jq" "tfe")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check required environment variables
    local required_vars=("TFE_TOKEN" "ARTIFACTORY_URL")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Environment variable $var is not set"
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to validate Terraform configuration
validate_terraform() {
    log "Validating Terraform configuration..."
    
    cd "$PROJECT_ROOT/terraform"
    
    # Initialize Terraform
    terraform init -input=false
    
    # Validate configuration
    terraform validate
    
    # Format check
    if ! terraform fmt -check -recursive; then
        warning "Terraform files are not properly formatted. Run 'terraform fmt -recursive' to fix."
    fi
    
    success "Terraform configuration validation passed"
}

# Function to perform security checks
security_checks() {
    log "Performing security checks..."
    
    # Check for hardcoded secrets
    if grep -r -i "password\|secret\|token" "$PROJECT_ROOT/terraform" --include="*.tf" --include="*.tfvars" | grep -v "variable\|description\|var\."; then
        error "Potential hardcoded secrets found in Terraform files"
        exit 1
    fi
    
    # Check HTTPS enforcement
    if ! grep -r "https://" "$PROJECT_ROOT/terraform" --include="*.tf" | grep -q "artifactory_url"; then
        error "HTTPS not enforced for Artifactory URL"
        exit 1
    fi
    
    # Check sensitive variable flags
    local sensitive_vars=("artifactory_access_token" "service_user_passwords" "ldap_manager_password")
    for var in "${sensitive_vars[@]}"; do
        if ! grep -A 5 "variable \"$var\"" "$PROJECT_ROOT/terraform/variables.tf" | grep -q "sensitive.*=.*true"; then
            error "Variable $var is not marked as sensitive"
            exit 1
        fi
    done
    
    success "Security checks passed"
}

# Function to backup current state
backup_state() {
    log "Creating backup of current state..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup Terraform state
    cd "$PROJECT_ROOT/terraform"
    terraform state pull > "$BACKUP_DIR/terraform.tfstate.backup"
    
    # Backup configuration files
    cp -r "$PROJECT_ROOT/terraform" "$BACKUP_DIR/"
    
    success "State backup created at $BACKUP_DIR"
}

# Function to test Artifactory connectivity
test_connectivity() {
    log "Testing Artifactory connectivity..."
    
    # Test basic connectivity
    if ! curl -s --max-time 30 -f "$ARTIFACTORY_URL/artifactory/api/system/ping" > /dev/null; then
        error "Cannot connect to Artifactory at $ARTIFACTORY_URL"
        exit 1
    fi
    
    # Test authentication (if token is available)
    if [[ -n "${ARTIFACTORY_ACCESS_TOKEN:-}" ]]; then
        local response
        response=$(curl -s --max-time 30 -H "Authorization: Bearer $ARTIFACTORY_ACCESS_TOKEN" \
                  "$ARTIFACTORY_URL/artifactory/api/system/version" || true)
        
        if [[ -z "$response" ]] || ! echo "$response" | jq -e .version > /dev/null 2>&1; then
            error "Authentication test failed"
            exit 1
        fi
        
        success "Authentication test passed"
    else
        warning "ARTIFACTORY_ACCESS_TOKEN not set, skipping authentication test"
    fi
    
    success "Connectivity tests passed"
}

# Function to plan Terraform changes
plan_changes() {
    log "Planning Terraform changes..."
    
    cd "$PROJECT_ROOT/terraform"
    
    # Generate plan
    local plan_file="/tmp/terraform-plan-$(date +%Y%m%d-%H%M%S).tfplan"
    terraform plan -out="$plan_file" -input=false
    
    # Show plan summary
    terraform show -json "$plan_file" | jq -r '
        .planned_values.root_module.resources[]? |
        select(.type | startswith("artifactory_")) |
        "\(.type): \(.values.key // .values.name // "unnamed")"
    ' | sort | uniq -c
    
    success "Terraform plan completed"
    echo "Plan file saved to: $plan_file"
}

# Function to apply Terraform changes
apply_changes() {
    log "Applying Terraform changes..."
    
    cd "$PROJECT_ROOT/terraform"
    
    # Apply with auto-approve (use with caution in production)
    if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then
        terraform apply -auto-approve -input=false
    else
        terraform apply -input=false
    fi
    
    success "Terraform apply completed"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Test repository access
    local repos=("docker-prod" "npm-prod" "maven-prod")
    for repo in "${repos[@]}"; do
        local response
        response=$(curl -s -H "Authorization: Bearer $ARTIFACTORY_ACCESS_TOKEN" \
                  "$ARTIFACTORY_URL/artifactory/api/repositories/$repo" || true)
        
        if [[ -z "$response" ]] || ! echo "$response" | jq -e .key > /dev/null 2>&1; then
            error "Repository $repo validation failed"
            exit 1
        fi
    done
    
    # Test service user creation
    local users=("ci-cd-production" "backup-service" "monitoring-service")
    for user in "${users[@]}"; do
        local response
        response=$(curl -s -H "Authorization: Bearer $ARTIFACTORY_ACCESS_TOKEN" \
                  "$ARTIFACTORY_URL/artifactory/api/security/users/$user" || true)
        
        if [[ -z "$response" ]] || ! echo "$response" | jq -e .name > /dev/null 2>&1; then
            error "Service user $user validation failed"
            exit 1
        fi
    done
    
    success "Deployment validation passed"
}

# Function to rollback deployment
rollback_deployment() {
    log "Rolling back deployment..."
    
    if [[ ! -f "$BACKUP_DIR/terraform.tfstate.backup" ]]; then
        error "No backup state file found"
        exit 1
    fi
    
    cd "$PROJECT_ROOT/terraform"
    
    # Restore state
    terraform state push "$BACKUP_DIR/terraform.tfstate.backup"
    
    # Apply the previous state
    terraform apply -auto-approve -input=false
    
    success "Rollback completed"
}

# Function to cleanup temporary files
cleanup() {
    log "Cleaning up temporary files..."
    
    # Remove temporary plan files
    find /tmp -name "terraform-plan-*.tfplan" -mtime +1 -delete 2>/dev/null || true
    
    # Remove old log files
    find /tmp -name "artifactory-deploy-*.log" -mtime +7 -delete 2>/dev/null || true
    
    # Remove old backup directories
    find /tmp -name "terraform-backup-*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    
    success "Cleanup completed"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

Commands:
    validate    - Validate Terraform configuration and perform security checks
    plan        - Plan Terraform changes
    apply       - Apply Terraform changes
    rollback    - Rollback to previous state
    full-deploy - Complete deployment process (validate, plan, apply, validate)

Options:
    --auto-approve  - Automatically approve Terraform apply
    --skip-backup   - Skip state backup
    --help          - Show this help message

Environment Variables:
    TFE_TOKEN                - Terraform Cloud API token
    ARTIFACTORY_URL          - Artifactory instance URL
    ARTIFACTORY_ACCESS_TOKEN - Artifactory access token (optional, for testing)
    AUTO_APPROVE            - Set to 'true' to auto-approve applies

Examples:
    $0 validate
    $0 plan
    $0 --auto-approve apply
    $0 full-deploy
    $0 rollback

EOF
}

# Main function
main() {
    local command=""
    local skip_backup=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto-approve)
                export AUTO_APPROVE=true
                shift
                ;;
            --skip-backup)
                skip_backup=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            validate|plan|apply|rollback|full-deploy)
                command=$1
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$command" ]]; then
        error "No command specified"
        usage
        exit 1
    fi
    
    # Create log file
    touch "$LOG_FILE"
    log "Starting Artifactory Terraform deployment script"
    log "Command: $command"
    log "Log file: $LOG_FILE"
    
    # Trap for cleanup
    trap cleanup EXIT
    
    # Execute based on command
    case $command in
        validate)
            check_prerequisites
            validate_terraform
            security_checks
            test_connectivity
            ;;
        plan)
            check_prerequisites
            validate_terraform
            security_checks
            test_connectivity
            plan_changes
            ;;
        apply)
            check_prerequisites
            validate_terraform
            security_checks
            test_connectivity
            if [[ "$skip_backup" == false ]]; then
                backup_state
            fi
            apply_changes
            validate_deployment
            ;;
        rollback)
            check_prerequisites
            rollback_deployment
            validate_deployment
            ;;
        full-deploy)
            check_prerequisites
            validate_terraform
            security_checks
            test_connectivity
            if [[ "$skip_backup" == false ]]; then
                backup_state
            fi
            plan_changes
            apply_changes
            validate_deployment
            ;;
    esac
    
    success "Script completed successfully"
}

# Execute main function with all arguments
main "$@"
