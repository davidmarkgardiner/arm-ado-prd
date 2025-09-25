#!/bin/bash

# k8s-health-check.sh - Check health of specific namespaces and their pods
# Usage: k8s-health-check [namespace1] [namespace2] ...
# If no namespaces provided, uses default list

set -euo pipefail

# Default namespaces to check
DEFAULT_NAMESPACES=("cert-manager" "azureserviceoperator-system")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl not found${NC}" >&2
        return 1
    fi
}

# Function to check if cluster is accessible
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}" >&2
        return 1
    fi
}

# Function to check namespace health
check_namespace_health() {
    local namespace=$1
    echo -e "${BLUE}Checking namespace: $namespace${NC}"

    # Check if namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        echo -e "  ${RED}✗ Namespace '$namespace' not found${NC}"
        return 1
    fi

    # Get all pods in the namespace
    local pods
    pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null || true)

    if [ -z "$pods" ]; then
        echo -e "  ${YELLOW}⚠ No pods found in namespace${NC}"
        return 0
    fi

    local total_pods=0
    local running_pods=0
    local ready_pods=0
    local failed_pods=0

    # Parse pod status
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            total_pods=$((total_pods + 1))
            local pod_name=$(echo "$line" | awk '{print $1}')
            local ready=$(echo "$line" | awk '{print $2}')
            local status=$(echo "$line" | awk '{print $3}')
            local restarts=$(echo "$line" | awk '{print $4}')

            case "$status" in
                "Running")
                    running_pods=$((running_pods + 1))
                    # Check if pod is ready (e.g., "1/1", "2/2")
                    if [[ "$ready" =~ ^([0-9]+)/([0-9]+)$ ]]; then
                        local ready_count=${BASH_REMATCH[1]}
                        local total_count=${BASH_REMATCH[2]}
                        if [ "$ready_count" = "$total_count" ]; then
                            ready_pods=$((ready_pods + 1))
                            echo -e "    ${GREEN}✓ $pod_name ($ready) - $status${NC}"
                        else
                            echo -e "    ${YELLOW}⚠ $pod_name ($ready) - $status (not ready)${NC}"
                        fi
                    else
                        echo -e "    ${GREEN}✓ $pod_name ($ready) - $status${NC}"
                        ready_pods=$((ready_pods + 1))
                    fi
                    ;;
                "Pending"|"ContainerCreating"|"PodInitializing")
                    echo -e "    ${YELLOW}⚠ $pod_name ($ready) - $status${NC}"
                    ;;
                "Failed"|"Error"|"CrashLoopBackOff"|"ImagePullBackOff")
                    failed_pods=$((failed_pods + 1))
                    echo -e "    ${RED}✗ $pod_name ($ready) - $status (restarts: $restarts)${NC}"
                    ;;
                "Completed"|"Succeeded")
                    echo -e "    ${GREEN}✓ $pod_name ($ready) - $status${NC}"
                    ready_pods=$((ready_pods + 1))
                    ;;
                *)
                    echo -e "    ${YELLOW}? $pod_name ($ready) - $status${NC}"
                    ;;
            esac
        fi
    done <<< "$pods"

    # Summary for this namespace
    echo -e "  Summary: ${GREEN}$ready_pods ready${NC}, ${BLUE}$running_pods running${NC}, ${RED}$failed_pods failed${NC} out of $total_pods total"
    echo ""

    # Return non-zero if there are failed pods
    [ $failed_pods -eq 0 ]
}

# Main function
main() {
    echo -e "${BLUE}Kubernetes Health Check${NC}"
    echo "========================="

    # Check prerequisites
    if ! check_kubectl || ! check_cluster; then
        return 1
    fi

    # Use provided namespaces or default
    local namespaces=("$@")
    if [ ${#namespaces[@]} -eq 0 ]; then
        namespaces=("${DEFAULT_NAMESPACES[@]}")
    fi

    local failed_namespaces=0
    local total_namespaces=${#namespaces[@]}

    # Check each namespace
    for namespace in "${namespaces[@]}"; do
        if ! check_namespace_health "$namespace"; then
            failed_namespaces=$((failed_namespaces + 1))
        fi
    done

    # Overall summary
    echo "========================="
    if [ $failed_namespaces -eq 0 ]; then
        echo -e "${GREEN}✓ All $total_namespaces namespace(s) healthy${NC}"
    else
        echo -e "${RED}✗ $failed_namespaces out of $total_namespaces namespace(s) have issues${NC}"
    fi

    return $failed_namespaces
}

# Run main function with all arguments
main "$@"