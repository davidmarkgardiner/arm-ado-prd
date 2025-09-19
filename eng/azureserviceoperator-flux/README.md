# Azure Service Operator with Flux Post-Build Substitution

This directory contains Azure Service Operator (ASO) manifests managed by Flux with post-build variable substitution. This approach leverages Flux's native variable substitution capabilities for GitOps-driven infrastructure deployment.

## 🏗️ Architecture Overview

This solution uses:
- **Azure Service Operator v2** with latest API versions
- **Flux Kustomization** with `postBuild.substituteFrom`
- **ConfigMaps and Secrets** for variable injection
- **Node Auto Provisioning (NAP)** for automatic node management
- **Cilium** for advanced networking

## 📁 Directory Structure

```
eng/azureserviceoperator-flux/
├── base/                           # Base ASO manifests
│   ├── cluster.yaml               # ManagedCluster with NAP
│   ├── resource-group.yaml        # ResourceGroup
│   ├── identity.yaml              # UserAssignedIdentities
│   ├── federated-credential.yaml  # FederatedIdentityCredentials
│   ├── agent-pool.yaml            # Additional agent pools
│   └── kustomization.yaml         # Base kustomization
├── overlays/                       # Environment-specific overlays
│   ├── dev/                       # Development environment
│   └── prod/                      # Production environment
├── configmaps/                     # Variable sources
│   ├── cluster-variables.yaml     # Non-sensitive variables
│   └── cluster-secrets-example.yaml # Sensitive variables template
└── README.md                      # This documentation
```

## 🔧 Key Features

### Modern ASO API Versions
- **containerservice.azure.com/v1api20240402preview** for latest AKS features
- **managedidentity.azure.com/v1api20230131** for managed identities
- **Node Auto Provisioning (NAP)** support

### Flux Post-Build Substitution
```yaml
postBuild:
  substitute:
    cluster_name: "aks-dev-eastus-001"
    location: "eastus"
  substituteFrom:
    - kind: ConfigMap
      name: cluster-variables
      optional: true
    - kind: Secret
      name: cluster-secrets
      optional: false
```

### Variable Syntax
Variables use Flux's format with bash-like features:
- `${variable_name}` - Simple substitution
- `${variable_name:=default}` - Default value
- `${variable_name:position:length}` - String manipulation

## 🚀 Deployment

### Prerequisites

1. **Flux installed** in the cluster
2. **Azure Service Operator v2** deployed
3. **Git repository** configured as Flux source

### Step 1: Create Secrets

Create the required secrets (use external-secrets, SOPS, or manual creation):

```bash
kubectl create secret generic cluster-secrets \
  --namespace=flux-system \
  --from-literal=ssh_public_key="ssh-rsa AAAAB3..." \
  --from-literal=subscription_id="12345678-..." \
  --from-literal=vnet_subnet_arm_id="/subscriptions/..." \
  --from-literal=admin_group_object_ids="cccccccc-..."
```

### Step 2: Deploy ConfigMaps

```bash
kubectl apply -f configmaps/cluster-variables.yaml
```

### Step 3: Apply Flux Kustomization

For development environment:
```bash
kubectl apply -f overlays/dev/kustomization.yaml
```

For production environment:
```bash
kubectl apply -f overlays/prod/kustomization.yaml
```

### Step 4: Monitor Deployment

```bash
# Watch Flux Kustomization
flux get kustomizations -w

# Check ASO resources
kubectl get managedclusters,resourcegroups,userassignedidentities -A

# Monitor cluster creation
kubectl describe managedcluster aks-dev-eastus-001 -n azure-system
```

## 🔒 Security Configuration

### Workload Identity
```yaml
securityProfile:
  workloadIdentity:
    enabled: true
```

### Node Security
```yaml
securityProfile:
  enableSecureBoot: true
  enableVTPM: true
```

### Network Security
```yaml
networkProfile:
  networkPolicy: cilium
  networkDataplane: cilium
```

### RBAC
```yaml
aadProfile:
  enableAzureRBAC: true
  managed: true
  adminGroupObjectIDs:
    - ${admin_group_object_ids}
```

## 🌐 Network Configuration

### Cilium with Overlay
```yaml
networkProfile:
  networkPlugin: azure
  networkPluginMode: overlay
  networkPolicy: cilium
  networkDataplane: cilium
```

### Service Mesh (Istio)
```yaml
serviceMeshProfile:
  mode: Istio
  istio:
    components:
      ingressGateways:
        - enabled: true
          mode: Internal
        - enabled: true
          mode: External
```

## 🔄 Node Auto Provisioning (NAP)

### Automatic Node Management
```yaml
nodeProvisioningProfile:
  mode: Auto
```

Benefits:
- **Automatic scaling** based on workload requirements
- **Cost optimization** with right-sized nodes
- **Reduced management** overhead
- **Intelligent scheduling** of workloads

## 📊 Monitoring and Observability

### Azure Monitor Integration
```yaml
azureMonitorProfile:
  metrics:
    enabled: true
    kubeStateMetrics:
      metricLabelsAllowlist: "namespaces=[*]"
```

### Defender for Containers
```yaml
securityProfile:
  defender:
    logAnalyticsWorkspaceResourceReference:
      armId: ${log_analytics_workspace_arm_id}
    securityMonitoring:
      enabled: true
```

## 🏷️ Variable Reference

### Core Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `cluster_name` | AKS cluster name | `aks-dev-eastus-001` |
| `resource_group_name` | Resource group | `rg-aks-dev-eastus-001` |
| `location` | Azure region | `eastus` |
| `environment` | Environment | `dev`, `prod` |

### Network Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `service_cidr` | Kubernetes services CIDR | `10.251.0.0/17` |
| `pod_cidr` | Pod CIDR for overlay | `10.251.128.0/17` |
| `dns_service_ip` | DNS service IP | `10.251.0.10` |

### Node Variables
| Variable | Description | Dev Default | Prod Default |
|----------|-------------|-------------|--------------|
| `system_node_vm_size` | System node VM size | `Standard_D4s_v5` | `Standard_D8s_v5` |
| `system_node_count` | System node count | `2` | `5` |
| `user_node_vm_size` | User node VM size | `Standard_D4s_v5` | `Standard_D16s_v5` |

### Sensitive Variables (Secrets)
| Variable | Description |
|----------|-------------|
| `ssh_public_key` | SSH public key for Linux VMs |
| `subscription_id` | Azure subscription ID |
| `vnet_subnet_arm_id` | Subnet ARM ID |
| `admin_group_object_ids` | AAD admin group IDs |

## 🔄 Environment Management

### Development Environment
- **Smaller nodes** for cost optimization
- **Relaxed health checks** with optional ConfigMaps
- **Faster deployment** with shorter timeouts

### Production Environment
- **Larger nodes** for performance
- **Strict health checks** with mandatory secrets
- **Longer timeouts** for stability
- **Enhanced monitoring** and alerting

## 🐛 Troubleshooting

### Flux Kustomization Issues

1. **Check Kustomization status**:
   ```bash
   flux get kustomizations aks-infrastructure-dev
   ```

2. **View events**:
   ```bash
   kubectl describe kustomization aks-infrastructure-dev -n flux-system
   ```

3. **Check variable substitution**:
   ```bash
   flux build kustomization aks-infrastructure-dev --dry-run
   ```

### ASO Resource Issues

1. **Check ASO controller**:
   ```bash
   kubectl logs -f deployment/azureserviceoperator-controller-manager -n azureserviceoperator-system
   ```

2. **Resource status**:
   ```bash
   kubectl describe managedcluster aks-dev-eastus-001 -n azure-system
   ```

3. **Events**:
   ```bash
   kubectl get events -n azure-system --sort-by='.lastTimestamp'
   ```

## 🔄 Updates and Maintenance

### Updating Cluster Configuration

1. **Modify variables** in ConfigMaps or Flux Kustomization
2. **Commit changes** to Git repository
3. **Flux reconciles** automatically

### Updating Kubernetes Version

```yaml
postBuild:
  substitute:
    kubernetes_version: "1.30"
```

### Adding Node Pools

Create additional `ManagedClustersAgentPool` resources and include in base kustomization.

## 🏆 Best Practices

### Variable Management
1. **Use ConfigMaps** for non-sensitive values
2. **Use Secrets** for sensitive data
3. **Leverage external-secrets** for secret management
4. **Use SOPS** for encrypted secrets in Git

### Environment Separation
1. **Separate Flux Kustomizations** per environment
2. **Different ConfigMaps/Secrets** per environment
3. **Environment-specific** health checks and timeouts

### Security
1. **Enable workload identity** for all clusters
2. **Use managed identities** instead of service principals
3. **Enable Azure RBAC** for Kubernetes access
4. **Regular updates** of Kubernetes versions

### Monitoring
1. **Enable Azure Monitor** metrics
2. **Configure Defender** for Containers
3. **Monitor Flux** reconciliation status
4. **Set up alerts** for cluster health

## 🔗 Related Documentation

- [Azure Service Operator v2](https://azure.github.io/azure-service-operator/)
- [Flux Post-Build Substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
- [AKS Node Auto Provisioning](https://docs.microsoft.com/en-us/azure/aks/node-auto-provisioning)
- [Cilium Azure CNI](https://docs.cilium.io/en/stable/installation/k8s-install-azure/)