#!/bin/bash

# Azure Service Operator with Flux Post-Build Substitution Deployment Script
set -euo pipefail

# Default values
ENVIRONMENT=""
DRY_RUN=false
VERBOSE=false
SKIP_SECRETS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AKS infrastructure using Azure Service Operator with Flux post-build substitution

OPTIONS:
    -e, --environment ENVIRONMENT    Environment to deploy (dev, staging, prod)
    -d, --dry-run                    Perform dry-run validation
    -v, --verbose                    Enable verbose output
    -s, --skip-secrets              Skip secret creation (assume they exist)
    -h, --help                       Show this help message

EXAMPLES:
    # Deploy development environment
    $0 -e dev

    # Dry-run for production
    $0 -e prod -d

    # Deploy with existing secrets
    $0 -e dev -s

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate requirements
validate_requirements() {
    log_info "Validating requirements..."

    # Check required commands
    local required_commands=("kubectl" "flux")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found"
            exit 1
        fi
    done

    # Check kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Check Flux installation
    if ! flux check &> /dev/null; then
        log_error "Flux is not properly installed in the cluster"
        exit 1
    fi

    # Check Azure Service Operator
    if ! kubectl get crd managedclusters.containerservice.azure.com &> /dev/null; then
        log_error "Azure Service Operator CRDs not found. Please install ASO first."
        exit 1
    fi

    log_success "All requirements validated"
}

# Create or validate secrets
manage_secrets() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        log_info "Skipping secret creation (--skip-secrets specified)"
        return 0
    fi

    log_info "Managing secrets for environment: $ENVIRONMENT"

    local secret_name="cluster-secrets"
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        secret_name="cluster-secrets-prod"
    fi

    # Check if secret exists
    if kubectl get secret "$secret_name" -n flux-system &> /dev/null; then
        log_warning "Secret $secret_name already exists. Skipping creation."
        return 0
    fi

    log_warning "Secret $secret_name does not exist."
    echo
    echo "Please create the secret manually with the following template:"
    echo
    cat << EOF
kubectl create secret generic $secret_name \\
  --namespace=flux-system \\
  --from-literal=ssh_public_key="ssh-rsa AAAAB3..." \\
  --from-literal=subscription_id="12345678-..." \\
  --from-literal=vnet_subnet_arm_id="/subscriptions/..." \\
  --from-literal=control_plane_identity_arm_id="/subscriptions/..." \\
  --from-literal=kubelet_identity_arm_id="/subscriptions/..." \\
  --from-literal=kubelet_identity_client_id="aaaaaaaa-..." \\
  --from-literal=kubelet_identity_object_id="bbbbbbbb-..." \\
  --from-literal=log_analytics_workspace_arm_id="/subscriptions/..." \\
  --from-literal=admin_group_object_ids="cccccccc-..." \\
  --from-literal=oidc_issuer_url="https://eastus.oic.prod-aks.azure.com/..."
EOF
    echo
    read -p "Press Enter after creating the secret to continue..."

    # Verify secret was created
    if ! kubectl get secret "$secret_name" -n flux-system &> /dev/null; then
        log_error "Secret $secret_name still not found. Please create it first."
        exit 1
    fi

    log_success "Secret validation completed"
}

# Deploy ConfigMaps
deploy_configmaps() {
    log_info "Deploying ConfigMaps..."

    if [[ "$DRY_RUN" == "true" ]]; then
        kubectl apply --dry-run=client -f configmaps/cluster-variables.yaml
    else
        kubectl apply -f configmaps/cluster-variables.yaml
    fi

    log_success "ConfigMaps deployed"
}

# Deploy Flux Kustomization
deploy_kustomization() {
    local overlay_path="overlays/${ENVIRONMENT}/kustomization.yaml"

    if [[ ! -f "$overlay_path" ]]; then
        log_error "Overlay not found: $overlay_path"
        exit 1
    fi

    log_info "Deploying Flux Kustomization for $ENVIRONMENT..."

    if [[ "$DRY_RUN" == "true" ]]; then
        kubectl apply --dry-run=client -f "$overlay_path"
        log_info "Dry-run completed for Flux Kustomization"
    else
        kubectl apply -f "$overlay_path"
        log_success "Flux Kustomization applied"
    fi
}

# Monitor deployment
monitor_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    local kustomization_name="aks-infrastructure-${ENVIRONMENT}"

    log_info "Monitoring deployment progress..."

    # Wait for Flux Kustomization to be ready
    log_info "Waiting for Flux Kustomization to reconcile..."
    if ! kubectl wait --for=condition=Ready kustomization/"$kustomization_name" \
         --namespace=flux-system --timeout=600s; then
        log_warning "Flux Kustomization not ready within timeout"

        # Show status for debugging
        log_info "Kustomization status:"
        kubectl describe kustomization "$kustomization_name" -n flux-system
        return 1
    fi

    log_success "Flux Kustomization is ready"

    # Wait for Azure resources
    local cluster_name
    cluster_name=$(kubectl get kustomization "$kustomization_name" -n flux-system -o jsonpath='{.spec.postBuild.substitute.cluster_name}' 2>/dev/null || echo "")

    if [[ -n "$cluster_name" ]]; then
        log_info "Waiting for ManagedCluster to be ready..."
        if ! kubectl wait --for=condition=Ready managedcluster/"$cluster_name" \
             --namespace=azure-system --timeout=1200s; then
            log_warning "ManagedCluster not ready within timeout"
        else
            log_success "ManagedCluster is ready"
        fi
    fi
}

# Show deployment status
show_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    local kustomization_name="aks-infrastructure-${ENVIRONMENT}"

    log_info "Deployment status:"

    echo -e "\n${BLUE}Flux Kustomization:${NC}"
    flux get kustomizations "$kustomization_name"

    echo -e "\n${BLUE}Azure Resources:${NC}"
    kubectl get managedclusters,resourcegroups,userassignedidentities -n azure-system -o wide

    echo -e "\n${BLUE}Recent Events:${NC}"
    kubectl get events -n azure-system --sort-by='.lastTimestamp' | tail -10

    # Get cluster credentials if cluster is ready
    local cluster_name
    cluster_name=$(kubectl get kustomization "$kustomization_name" -n flux-system -o jsonpath='{.spec.postBuild.substitute.cluster_name}' 2>/dev/null || echo "")

    if [[ -n "$cluster_name" ]] && kubectl get managedcluster "$cluster_name" -n azure-system &> /dev/null; then
        local cluster_state
        cluster_state=$(kubectl get managedcluster "$cluster_name" -n azure-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

        if [[ "$cluster_state" == "True" ]]; then
            echo -e "\n${GREEN}🎉 Cluster is ready! Get credentials with:${NC}"
            echo "az aks get-credentials --resource-group \$(kubectl get kustomization $kustomization_name -n flux-system -o jsonpath='{.spec.postBuild.substitute.resource_group_name}') --name $cluster_name"
        fi
    fi
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            -s|--skip-secrets)
                SKIP_SECRETS=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required"
        usage
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Environment must be 'dev', 'staging', or 'prod'"
        exit 1
    fi

    # Print banner
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║              Azure Service Operator + Flux Deployment                       ║"
    echo "║                                                                              ║"
    echo "║ Environment: $ENVIRONMENT"
    echo "║ Dry Run: $DRY_RUN"
    echo "║ Skip Secrets: $SKIP_SECRETS"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Execute deployment steps
    validate_requirements
    manage_secrets
    deploy_configmaps
    deploy_kustomization
    monitor_deployment
    show_status

    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Deployment completed successfully!"
        echo
        log_info "Next steps:"
        echo "  1. Monitor Flux: flux get kustomizations -w"
        echo "  2. Check ASO: kubectl get managedclusters -n azure-system"
        echo "  3. View logs: kubectl logs -f deployment/azureserviceoperator-controller-manager -n azureserviceoperator-system"
    else
        log_success "Dry-run completed successfully!"
        echo
        log_info "To perform actual deployment, run the same command without --dry-run flag"
    fi
}

# Change to script directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Run main function
main "$@"