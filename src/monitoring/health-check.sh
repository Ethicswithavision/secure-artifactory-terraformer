
#!/bin/bash
# Artifactory Health Check Script
# Monitors Artifactory instance health and sends alerts

set -euo pipefail

# Configuration
ARTIFACTORY_URL="${ARTIFACTORY_URL:-}"
ACCESS_TOKEN="${ARTIFACTORY_ACCESS_TOKEN:-}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
LOG_FILE="/var/log/artifactory-health.log"
METRICS_FILE="/tmp/artifactory-metrics.json"

# Health check thresholds
RESPONSE_TIME_THRESHOLD=5000  # milliseconds
DISK_USAGE_THRESHOLD=85       # percentage
MEMORY_USAGE_THRESHOLD=90     # percentage
ERROR_RATE_THRESHOLD=5        # percentage

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
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

# Function to send alerts
send_alert() {
    local severity=$1
    local message=$2
    local details=$3
    
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "{
                \"severity\": \"$severity\",
                \"service\": \"artifactory\",
                \"message\": \"$message\",
                \"details\": \"$details\",
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }" \
            "$ALERT_WEBHOOK" || warning "Failed to send alert"
    fi
    
    log "ALERT [$severity]: $message - $details"
}

# Function to check basic connectivity
check_connectivity() {
    log "Checking Artifactory connectivity..."
    
    local start_time=$(date +%s%3N)
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" --max-time 30 \
        "$ARTIFACTORY_URL/artifactory/api/system/ping" 2>/dev/null || echo "000")
    
    http_code="${response: -3}"
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    if [[ "$http_code" != "200" ]]; then
        send_alert "CRITICAL" "Artifactory connectivity failed" "HTTP code: $http_code"
        return 1
    fi
    
    if [[ $response_time -gt $RESPONSE_TIME_THRESHOLD ]]; then
        send_alert "WARNING" "High response time" "Response time: ${response_time}ms"
    fi
    
    echo "{\"connectivity\": {\"status\": \"ok\", \"response_time_ms\": $response_time}}" > "$METRICS_FILE"
    success "Connectivity check passed (${response_time}ms)"
    return 0
}

# Function to check authentication
check_authentication() {
    log "Checking Artifactory authentication..."
    
    if [[ -z "$ACCESS_TOKEN" ]]; then
        warning "Access token not provided, skipping authentication check"
        return 0
    fi
    
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" --max-time 30 \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$ARTIFACTORY_URL/artifactory/api/system/version" 2>/dev/null || echo "000")
    
    http_code="${response: -3}"
    
    if [[ "$http_code" != "200" ]]; then
        send_alert "CRITICAL" "Authentication failed" "HTTP code: $http_code"
        return 1
    fi
    
    success "Authentication check passed"
    return 0
}

# Function to check system health
check_system_health() {
    log "Checking Artifactory system health..."
    
    if [[ -z "$ACCESS_TOKEN" ]]; then
        warning "Access token not provided, skipping system health check"
        return 0
    fi
    
    local health_response
    health_response=$(curl -s --max-time 30 \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$ARTIFACTORY_URL/artifactory/api/system/info" 2>/dev/null || echo "{}")
    
    if ! echo "$health_response" | jq -e . >/dev/null 2>&1; then
        send_alert "CRITICAL" "Invalid system health response" "Response: $health_response"
        return 1
    fi
    
    # Extract system information
    local version=$(echo "$health_response" | jq -r '.version // "unknown"')
    local license_type=$(echo "$health_response" | jq -r '.licenseInfo.type // "unknown"')
    local license_valid=$(echo "$health_response" | jq -r '.licenseInfo.validThrough // "unknown"')
    
    # Update metrics
    jq --arg version "$version" \
       --arg license_type "$license_type" \
       --arg license_valid "$license_valid" \
       '.system_health = {
           "version": $version,
           "license_type": $license_type,
           "license_valid": $license_valid,
           "status": "ok"
       }' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    
    success "System health check passed (version: $version)"
    return 0
}

# Function to check storage usage
check_storage() {
    log "Checking Artifactory storage usage..."
    
    if [[ -z "$ACCESS_TOKEN" ]]; then
        warning "Access token not provided, skipping storage check"
        return 0
    fi
    
    local storage_response
    storage_response=$(curl -s --max-time 30 \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$ARTIFACTORY_URL/artifactory/api/storageinfo" 2>/dev/null || echo "{}")
    
    if ! echo "$storage_response" | jq -e . >/dev/null 2>&1; then
        send_alert "WARNING" "Could not retrieve storage information" "Response: $storage_response"
        return 1
    fi
    
    # Calculate storage usage percentage
    local used_space=$(echo "$storage_response" | jq -r '.binariesSummary.binariesSize // "0"')
    local total_space=$(echo "$storage_response" | jq -r '.fileStoreSummary.totalSpace // "1"')
    
    # Convert to bytes if needed and calculate percentage
    local usage_percent=0
    if [[ "$total_space" != "0" && "$total_space" != "1" ]]; then
        usage_percent=$(echo "scale=2; ($used_space * 100) / $total_space" | bc 2>/dev/null || echo "0")
    fi
    
    # Check against threshold
    if (( $(echo "$usage_percent > $DISK_USAGE_THRESHOLD" | bc -l) )); then
        send_alert "WARNING" "High disk usage" "Usage: ${usage_percent}%"
    fi
    
    # Update metrics
    jq --arg usage_percent "$usage_percent" \
       --arg used_space "$used_space" \
       --arg total_space "$total_space" \
       '.storage = {
           "usage_percent": ($usage_percent | tonumber),
           "used_space": ($used_space | tonumber),
           "total_space": ($total_space | tonumber),
           "status": "ok"
       }' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    
    success "Storage check passed (${usage_percent}% used)"
    return 0
}

# Function to check repository status
check_repositories() {
    log "Checking repository status..."
    
    if [[ -z "$ACCESS_TOKEN" ]]; then
        warning "Access token not provided, skipping repository check"
        return 0
    fi
    
    local repos_response
    repos_response=$(curl -s --max-time 30 \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$ARTIFACTORY_URL/artifactory/api/repositories" 2>/dev/null || echo "[]")
    
    if ! echo "$repos_response" | jq -e . >/dev/null 2>&1; then
        send_alert "WARNING" "Could not retrieve repository information" "Response: $repos_response"
        return 1
    fi
    
    local repo_count=$(echo "$repos_response" | jq '. | length')
    local local_repos=$(echo "$repos_response" | jq '[.[] | select(.type == "LOCAL")] | length')
    local remote_repos=$(echo "$repos_response" | jq '[.[] | select(.type == "REMOTE")] | length')
    local virtual_repos=$(echo "$repos_response" | jq '[.[] | select(.type == "VIRTUAL")] | length')
    
    # Update metrics
    jq --arg total "$repo_count" \
       --arg local "$local_repos" \
       --arg remote "$remote_repos" \
       --arg virtual "$virtual_repos" \
       '.repositories = {
           "total": ($total | tonumber),
           "local": ($local | tonumber),
           "remote": ($remote | tonumber),
           "virtual": ($virtual | tonumber),
           "status": "ok"
       }' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    
    success "Repository check passed ($repo_count repositories)"
    return 0
}

# Function to check service status
check_services() {
    log "Checking Artifactory services..."
    
    if [[ -z "$ACCESS_TOKEN" ]]; then
        warning "Access token not provided, skipping service check"
        return 0
    fi
    
    # Check various service endpoints
    local services=("system/ping" "system/version" "system/info")
    local service_status="ok"
    local failed_services=()
    
    for service in "${services[@]}"; do
        local response
        local http_code
        
        response=$(curl -s -w "%{http_code}" --max-time 10 \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            "$ARTIFACTORY_URL/artifactory/api/$service" 2>/dev/null || echo "000")
        
        http_code="${response: -3}"
        
        if [[ "$http_code" != "200" ]]; then
            failed_services+=("$service")
            service_status="degraded"
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        send_alert "WARNING" "Some services are not responding" "Failed services: ${failed_services[*]}"
    fi
    
    # Update metrics
    jq --arg status "$service_status" \
       --argjson failed_count "${#failed_services[@]}" \
       '.services = {
           "status": $status,
           "failed_count": $failed_count,
           "total_checked": 3
       }' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    
    success "Service check completed (status: $service_status)"
    return 0
}

# Function to generate health report
generate_report() {
    log "Generating health report..."
    
    if [[ ! -f "$METRICS_FILE" ]]; then
        error "Metrics file not found"
        return 1
    fi
    
    local report_file="/tmp/artifactory-health-report-$(date +%Y%m%d-%H%M%S).json"
    
    # Add timestamp and overall status to metrics
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.timestamp = $timestamp | .overall_status = "ok"' \
       "$METRICS_FILE" > "$report_file"
    
    # Print summary
    echo "=== Artifactory Health Report ==="
    echo "Timestamp: $(date)"
    echo "Report file: $report_file"
    echo ""
    
    if command -v jq >/dev/null 2>&1; then
        echo "Connectivity: $(jq -r '.connectivity.status // "unknown"' "$report_file")"
        echo "System Health: $(jq -r '.system_health.status // "unknown"' "$report_file")"
        echo "Storage Usage: $(jq -r '.storage.usage_percent // "unknown"' "$report_file")%"
        echo "Repositories: $(jq -r '.repositories.total // "unknown"' "$report_file")"
        echo "Services: $(jq -r '.services.status // "unknown"' "$report_file")"
    fi
    
    success "Health report generated: $report_file"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --connectivity  - Check connectivity only
    --auth         - Check authentication only
    --system       - Check system health only
    --storage      - Check storage usage only
    --repositories - Check repository status only
    --services     - Check service status only
    --report       - Generate health report only
    --all          - Run all checks (default)
    --help         - Show this help message

Environment Variables:
    ARTIFACTORY_URL          - Artifactory instance URL (required)
    ARTIFACTORY_ACCESS_TOKEN - Access token for authenticated checks
    ALERT_WEBHOOK           - Webhook URL for sending alerts

Examples:
    $0 --all
    $0 --connectivity --auth
    $0 --storage --repositories
    $0 --report

EOF
}

# Main function
main() {
    local checks=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --connectivity)
                checks+=("connectivity")
                shift
                ;;
            --auth)
                checks+=("auth")
                shift
                ;;
            --system)
                checks+=("system")
                shift
                ;;
            --storage)
                checks+=("storage")
                shift
                ;;
            --repositories)
                checks+=("repositories")
                shift
                ;;
            --services)
                checks+=("services")
                shift
                ;;
            --report)
                checks+=("report")
                shift
                ;;
            --all)
                checks=("connectivity" "auth" "system" "storage" "repositories" "services" "report")
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Default to all checks if none specified
    if [[ ${#checks[@]} -eq 0 ]]; then
        checks=("connectivity" "auth" "system" "storage" "repositories" "services" "report")
    fi
    
    # Validate required environment variables
    if [[ -z "$ARTIFACTORY_URL" ]]; then
        error "ARTIFACTORY_URL environment variable is required"
        exit 1
    fi
    
    # Initialize metrics file
    echo '{}' > "$METRICS_FILE"
    
    log "Starting Artifactory health check"
    log "Target: $ARTIFACTORY_URL"
    
    local exit_code=0
    
    # Execute checks
    for check in "${checks[@]}"; do
        case $check in
            connectivity)
                check_connectivity || exit_code=1
                ;;
            auth)
                check_authentication || exit_code=1
                ;;
            system)
                check_system_health || exit_code=1
                ;;
            storage)
                check_storage || exit_code=1
                ;;
            repositories)
                check_repositories || exit_code=1
                ;;
            services)
                check_services || exit_code=1
                ;;
            report)
                generate_report || exit_code=1
                ;;
        esac
    done
    
    if [[ $exit_code -eq 0 ]]; then
        success "All health checks completed successfully"
    else
        error "Some health checks failed"
    fi
    
    exit $exit_code
}

# Execute main function with all arguments
main "$@"
