# Management Cluster Azure RBAC Architecture

## Overview

The management cluster serves as the **central control plane** for deploying and managing infrastructure across multiple Azure subscriptions. This document defines the comprehensive Azure RBAC permissions required for the management cluster's identities to provision and manage the entire environment.

## 🏗️ Multi-Subscription Architecture

```
Management Subscription
├── Management Cluster (AKS)
├── Azure Service Operator
├── Flux GitOps
└── Management Identities (UAMIs/SPNs)
    ↓
    Cross-Subscription Deployments
    ├── Networking Subscription
    │   ├── Virtual Networks
    │   ├── Subnets & NSGs
    │   ├── Private DNS Zones
    │   └── Network Watchers
    ├── Compute Subscriptions (Dev/Staging/Prod)
    │   ├── AKS Worker Clusters
    │   ├── Node Resource Groups
    │   ├── Load Balancers
    │   └── Public IPs
    ├── Monitoring Subscription
    │   ├── Log Analytics Workspaces
    │   ├── Application Insights
    │   ├── Azure Monitor
    │   └── Grafana/Prometheus
    ├── Security Subscription
    │   ├── Key Vaults
    │   ├── Azure Security Center
    │   ├── Microsoft Defender
    │   └── Azure Policy
    └── Shared Services Subscription
        ├── Container Registry
        ├── Storage Accounts
        ├── DNS Zones
        └── Backup Vaults
```

## 🔐 Identity Architecture

### Primary Identities

```yaml
# Management Cluster System Identity
management_cluster_system_identity:
  type: SystemAssigned
  scope: Management Subscription
  purpose: Core cluster operations

# Azure Service Operator Identity
aso_uami:
  type: UserAssigned
  scope: Cross-subscription
  purpose: Azure resource provisioning via ASO

# Flux GitOps Identity
flux_uami:
  type: UserAssigned
  scope: Cross-subscription
  purpose: GitOps deployments and configuration

# Workload Identity for Applications
workload_identity_uami:
  type: UserAssigned
  scope: Application-specific
  purpose: Application access to Azure services
```

### Identity Assignment Strategy

```yaml
# ASO Identity Configuration
apiVersion: managedidentity.azure.com/v1api20230131
kind: UserAssignedIdentity
metadata:
  name: aso-cross-subscription-identity
  namespace: azure-system
spec:
  location: ${location}
  owner:
    name: ${management_resource_group}
  tags:
    purpose: "azure-service-operator"
    scope: "cross-subscription"
    security-level: "high"

---
# Federated Identity Credential for ASO
apiVersion: managedidentity.azure.com/v1api20230131
kind: FederatedIdentityCredential
metadata:
  name: aso-workload-identity
  namespace: azure-system
spec:
  owner:
    name: aso-cross-subscription-identity
  issuer: ${oidc_issuer_url}
  subject: "system:serviceaccount:azureserviceoperator-system:azureserviceoperator-default"
  audiences:
    - "api://AzureADTokenExchange"
```

## 🎯 RBAC Permission Matrix

### Cross-Subscription Built-in Roles

| Identity | Subscription | Role | Justification |
|----------|--------------|------|---------------|
| ASO UAMI | All Target Subscriptions | Contributor | Full resource lifecycle management |
| ASO UAMI | All Target Subscriptions | User Access Administrator | Manage RBAC assignments for created resources |
| Flux UAMI | All Target Subscriptions | Reader | Monitor resource state |
| Flux UAMI | Management Subscription | Contributor | Manage Flux resources |
| Management Cluster | Management Subscription | Contributor | Self-management capabilities |

### Subscription-Specific Permissions

#### Networking Subscription
```json
{
  "assignmentName": "aso-networking-permissions",
  "roleDefinitionId": "/subscriptions/{subscription-id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7",
  "scope": "/subscriptions/{networking-subscription-id}",
  "principalId": "{aso-uami-object-id}",
  "principalType": "ServicePrincipal",
  "description": "Network Contributor for networking resources"
}
```

Required permissions for networking:
- **Network Contributor**: VNets, subnets, NSGs, route tables
- **DNS Zone Contributor**: Private DNS zones
- **Private DNS Zone Contributor**: Private DNS management
- **Network Watcher Contributor**: Network monitoring

#### Compute Subscriptions (Dev/Staging/Prod)
```json
{
  "assignmentName": "aso-compute-permissions",
  "roleDefinitionId": "/subscriptions/{subscription-id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
  "scope": "/subscriptions/{compute-subscription-id}",
  "principalId": "{aso-uami-object-id}",
  "principalType": "ServicePrincipal",
  "description": "Contributor for AKS and compute resources"
}
```

Required permissions for compute:
- **Contributor**: AKS clusters, managed disks, load balancers
- **Azure Kubernetes Service Contributor**: AKS-specific operations
- **Managed Identity Contributor**: Create and manage identities

#### Monitoring Subscription
```json
{
  "assignmentName": "aso-monitoring-permissions",
  "roleDefinitionId": "/subscriptions/{subscription-id}/providers/Microsoft.Authorization/roleDefinitions/73c42c96-874c-492b-b04d-ab87d138a893",
  "scope": "/subscriptions/{monitoring-subscription-id}",
  "principalId": "{aso-uami-object-id}",
  "principalType": "ServicePrincipal",
  "description": "Log Analytics Contributor for monitoring"
}
```

Required permissions for monitoring:
- **Log Analytics Contributor**: Workspaces and queries
- **Monitoring Contributor**: Azure Monitor resources
- **Application Insights Component Contributor**: App Insights
- **Grafana Admin**: Managed Grafana instances

### Custom Role Definitions

#### ASO Cross-Subscription Deployer
```json
{
  "Name": "ASO Cross-Subscription Deployer",
  "Id": "custom-aso-deployer-role",
  "IsCustom": true,
  "Description": "Custom role for Azure Service Operator cross-subscription deployments",
  "Actions": [
    // Resource Management
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/*",
    "Microsoft.Resources/deployments/*",
    "Microsoft.Resources/templateSpecs/*",

    // AKS Management
    "Microsoft.ContainerService/managedClusters/*",
    "Microsoft.ContainerService/managedclustersnapshots/*",

    // Networking
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.Network/virtualNetworks/subnets/*",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/networkSecurityGroups/*",
    "Microsoft.Network/privateDnsZones/*",
    "Microsoft.Network/privateEndpoints/*",

    // Identity Management
    "Microsoft.ManagedIdentity/userAssignedIdentities/*",
    "Microsoft.Authorization/roleAssignments/read",
    "Microsoft.Authorization/roleAssignments/write",
    "Microsoft.Authorization/roleAssignments/delete",
    "Microsoft.Authorization/roleDefinitions/read",

    // Monitoring
    "Microsoft.OperationalInsights/workspaces/*",
    "Microsoft.Insights/components/*",
    "Microsoft.AlertsManagement/*",

    // Security
    "Microsoft.KeyVault/vaults/*",
    "Microsoft.Security/assessments/read",
    "Microsoft.Security/policies/read",

    // Storage
    "Microsoft.Storage/storageAccounts/*",
    "Microsoft.ContainerRegistry/registries/*",

    // Policy and Governance
    "Microsoft.PolicyInsights/*",
    "Microsoft.Management/managementGroups/read"
  ],
  "NotActions": [
    // Prevent elevation of privilege
    "Microsoft.Authorization/*/Delete",
    "Microsoft.Authorization/elevateAccess/Action",
    "Microsoft.Blueprint/blueprintAssignments/write",
    "Microsoft.Blueprint/blueprintAssignments/delete",

    // Prevent subscription-level changes
    "Microsoft.Subscription/*",
    "Microsoft.Billing/*",
    "Microsoft.Consumption/*"
  ],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/{networking-subscription-id}",
    "/subscriptions/{compute-dev-subscription-id}",
    "/subscriptions/{compute-staging-subscription-id}",
    "/subscriptions/{compute-prod-subscription-id}",
    "/subscriptions/{monitoring-subscription-id}",
    "/subscriptions/{security-subscription-id}",
    "/subscriptions/{shared-services-subscription-id}"
  ]
}
```

#### Flux GitOps Operator
```json
{
  "Name": "Flux GitOps Operator",
  "Id": "custom-flux-operator-role",
  "IsCustom": true,
  "Description": "Role for Flux to monitor and reconcile Azure resources",
  "Actions": [
    // Read access for monitoring
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/deployments/read",

    // AKS read access
    "Microsoft.ContainerService/managedClusters/read",
    "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action",

    // Networking read access
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/subnets/read",

    // Identity read access
    "Microsoft.ManagedIdentity/userAssignedIdentities/read",

    // Limited write access for Flux resources
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/deployments/write"
  ],
  "AssignableScopes": [
    "/subscriptions/{management-subscription-id}",
    "/subscriptions/{networking-subscription-id}",
    "/subscriptions/{compute-dev-subscription-id}",
    "/subscriptions/{compute-staging-subscription-id}",
    "/subscriptions/{compute-prod-subscription-id}",
    "/subscriptions/{monitoring-subscription-id}"
  ]
}
```

## 🔧 Implementation Strategy

### 1. Management Group Level Assignment
```bash
# Assign at Management Group level for efficiency
az role assignment create \
  --assignee-object-id ${aso_uami_object_id} \
  --assignee-principal-type ServicePrincipal \
  --role "ASO Cross-Subscription Deployer" \
  --scope "/providers/Microsoft.Management/managementGroups/${management_group_id}"
```

### 2. Subscription Level Assignments
```bash
# Script to assign roles across multiple subscriptions
#!/bin/bash

SUBSCRIPTIONS=(
  "networking-subscription-id"
  "compute-dev-subscription-id"
  "compute-staging-subscription-id"
  "compute-prod-subscription-id"
  "monitoring-subscription-id"
  "security-subscription-id"
  "shared-services-subscription-id"
)

ASO_UAMI_OBJECT_ID="your-aso-uami-object-id"
FLUX_UAMI_OBJECT_ID="your-flux-uami-object-id"

for subscription_id in "${SUBSCRIPTIONS[@]}"; do
  echo "Assigning roles to subscription: $subscription_id"

  # ASO permissions
  az role assignment create \
    --assignee-object-id $ASO_UAMI_OBJECT_ID \
    --assignee-principal-type ServicePrincipal \
    --role "Contributor" \
    --scope "/subscriptions/$subscription_id"

  az role assignment create \
    --assignee-object-id $ASO_UAMI_OBJECT_ID \
    --assignee-principal-type ServicePrincipal \
    --role "User Access Administrator" \
    --scope "/subscriptions/$subscription_id"

  # Flux permissions
  az role assignment create \
    --assignee-object-id $FLUX_UAMI_OBJECT_ID \
    --assignee-principal-type ServicePrincipal \
    --role "Reader" \
    --scope "/subscriptions/$subscription_id"
done
```

### 3. Resource Provider Registration
```bash
# Ensure required resource providers are registered
RESOURCE_PROVIDERS=(
  "Microsoft.ContainerService"
  "Microsoft.Network"
  "Microsoft.ManagedIdentity"
  "Microsoft.OperationalInsights"
  "Microsoft.Insights"
  "Microsoft.KeyVault"
  "Microsoft.Storage"
  "Microsoft.Authorization"
  "Microsoft.PolicyInsights"
  "Microsoft.AlertsManagement"
)

for subscription_id in "${SUBSCRIPTIONS[@]}"; do
  for provider in "${RESOURCE_PROVIDERS[@]}"; do
    az provider register --namespace $provider --subscription $subscription_id
  done
done
```

## 🔒 Security Considerations

### Principle of Least Privilege
```yaml
# Environment-specific identity constraints
production_identity:
  allowed_resource_groups:
    - "rg-aks-prod-*"
    - "rg-monitoring-prod-*"
  denied_actions:
    - "Microsoft.Authorization/roleAssignments/delete"
    - "Microsoft.Resources/subscriptions/*/delete"

development_identity:
  allowed_resource_groups:
    - "rg-aks-dev-*"
    - "rg-monitoring-dev-*"
  additional_permissions:
    - "Microsoft.Resources/*/delete"  # Allow resource cleanup in dev
```

### Conditional Access Policies
```json
{
  "displayName": "Management Cluster Identity Access",
  "state": "enabled",
  "conditions": {
    "applications": {
      "includeApplications": ["https://management.azure.com/"]
    },
    "users": {
      "includeUsers": ["{aso-uami-object-id}", "{flux-uami-object-id}"]
    },
    "locations": {
      "includeLocations": ["{azure-region-location-id}"]
    }
  },
  "grantControls": {
    "operator": "AND",
    "builtInControls": ["mfa", "compliantDevice"]
  }
}
```

### RBAC Monitoring and Auditing
```yaml
# Azure Policy for RBAC monitoring
policyDefinition:
  displayName: "Monitor Management Cluster RBAC Changes"
  mode: "All"
  policyRule:
    if:
      allOf:
        - field: "type"
          equals: "Microsoft.Authorization/roleAssignments"
        - field: "Microsoft.Authorization/roleAssignments/principalId"
          in: ["{aso-uami-object-id}", "{flux-uami-object-id}"]
    then:
      effect: "audit"
      details:
        type: "Microsoft.Insights/activityLogAlerts"
```

## 📋 Validation and Testing

### Permission Validation Script
```bash
#!/bin/bash
# Validate cross-subscription permissions

ASO_UAMI_OBJECT_ID="your-aso-uami-object-id"
TEST_SUBSCRIPTION="target-subscription-id"

echo "Testing ASO permissions on subscription: $TEST_SUBSCRIPTION"

# Test resource group creation
az group create \
  --name "test-rbac-validation" \
  --location "eastus" \
  --subscription $TEST_SUBSCRIPTION \
  --assignee-object-id $ASO_UAMI_OBJECT_ID

# Test AKS cluster creation (dry-run)
az aks create \
  --resource-group "test-rbac-validation" \
  --name "test-cluster" \
  --node-count 1 \
  --subscription $TEST_SUBSCRIPTION \
  --assignee-object-id $ASO_UAMI_OBJECT_ID \
  --dry-run

# Test networking permissions
az network vnet create \
  --resource-group "test-rbac-validation" \
  --name "test-vnet" \
  --subscription $TEST_SUBSCRIPTION \
  --assignee-object-id $ASO_UAMI_OBJECT_ID \
  --dry-run

# Cleanup
az group delete \
  --name "test-rbac-validation" \
  --subscription $TEST_SUBSCRIPTION \
  --yes --no-wait
```

### Azure Service Operator RBAC Test
```yaml
# Test ASO can create resources across subscriptions
apiVersion: resources.azure.com/v1api20200601
kind: ResourceGroup
metadata:
  name: rbac-test-rg
  namespace: azure-system
  annotations:
    serviceoperator.azure.com/credential-from: aso-cross-subscription-identity
spec:
  azureName: rbac-test-rg
  location: eastus
  # This should be created in the target subscription
  # based on the UAMI's permissions

---
# Test network resource creation
apiVersion: network.azure.com/v1api20201101
kind: VirtualNetwork
metadata:
  name: rbac-test-vnet
  namespace: azure-system
spec:
  owner:
    name: rbac-test-rg
  location: eastus
  addressSpace:
    addressPrefixes:
      - "10.0.0.0/16"
```

## 🚨 Security Alerts and Monitoring

### Key Metrics to Monitor
```yaml
# Azure Monitor queries for RBAC monitoring
rbac_monitoring_queries:
  high_privilege_assignments:
    query: |
      AzureActivity
      | where OperationNameValue == "Microsoft.Authorization/roleAssignments/write"
      | where Properties contains "aso-cross-subscription-identity"
      | project TimeGenerated, Caller, ResourceGroup, Properties

  failed_permissions:
    query: |
      AzureActivity
      | where ActivityStatusValue == "Failure"
      | where Properties contains "aso-cross-subscription-identity"
      | project TimeGenerated, OperationNameValue, ActivityStatusValue, Properties

  cross_subscription_access:
    query: |
      AzureActivity
      | where Caller contains "aso-cross-subscription-identity"
      | summarize count() by SubscriptionId, ResourceGroup
      | order by count_ desc
```

### Automated Compliance Checking
```bash
#!/bin/bash
# Daily RBAC compliance check

echo "Checking RBAC compliance for management cluster identities..."

# Check for unexpected role assignments
unexpected_roles=$(az role assignment list \
  --assignee $ASO_UAMI_OBJECT_ID \
  --query "[?roleDefinitionName!='Contributor' && roleDefinitionName!='User Access Administrator'].roleDefinitionName" \
  --output tsv)

if [ -n "$unexpected_roles" ]; then
  echo "WARNING: Unexpected roles found: $unexpected_roles"
  # Send alert to security team
fi

# Check for assignments outside expected scopes
out_of_scope=$(az role assignment list \
  --assignee $ASO_UAMI_OBJECT_ID \
  --query "[?!starts_with(scope, '/subscriptions/expected-subscription-prefix')]" \
  --output table)

if [ -n "$out_of_scope" ]; then
  echo "WARNING: Out of scope assignments found"
  echo "$out_of_scope"
fi
```

## 📈 Best Practices

### 1. Use Management Groups
- Assign roles at management group level when possible
- Reduces individual subscription assignments
- Easier to manage at scale

### 2. Custom Roles Over Built-in
- Create specific roles for ASO and Flux
- Follow principle of least privilege
- Regular review and updates

### 3. Workload Identity
- Prefer User Assigned Managed Identities
- Use Federated Identity Credentials
- Avoid long-lived secrets

### 4. Regular Auditing
- Monthly RBAC reviews
- Automated compliance checking
- Alert on privilege escalation

### 5. Environment Separation
- Different identities per environment
- Scoped permissions by environment
- Production requires additional approvals

## 🔄 Maintenance and Updates

### Quarterly Review Process
1. **Audit all role assignments** across subscriptions
2. **Review custom role definitions** for scope creep
3. **Test permission validation** scripts
4. **Update documentation** with any changes
5. **Security team review** of privileged access

### Breaking Changes Handling
1. **Test in development** environment first
2. **Gradual rollout** across environments
3. **Rollback plan** documented
4. **Monitor for failures** during transition

---

## 🎯 Conclusion

The management cluster's cross-subscription RBAC design must balance **security with functionality**. The proposed architecture:

✅ **Enables full lifecycle management** across all subscriptions
✅ **Maintains principle of least privilege** through custom roles
✅ **Provides comprehensive auditing** and monitoring
✅ **Supports automated compliance** checking
✅ **Allows for secure delegation** to different teams

This design ensures the management cluster can effectively orchestrate the entire Azure environment while maintaining strong security controls and governance.

**Remember**: RBAC is not "set and forget" - it requires ongoing monitoring, auditing, and adjustment as the environment evolves.