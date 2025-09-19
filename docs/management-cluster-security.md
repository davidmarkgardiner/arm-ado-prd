# Management Cluster Security Framework

## Overview

The management cluster is the crown jewel of the infrastructure - it controls all worker clusters through GitOps. A compromise here affects the entire platform. This document outlines a comprehensive security framework implementing **Defense in Depth** principles.

## 🎯 Security Objectives

1. **Prevent unauthorized access** to management cluster
2. **Protect Git repositories** from malicious commits
3. **Implement least privilege** access controls
4. **Enable comprehensive auditing** of all actions
5. **Ensure secure communication** channels
6. **Maintain operational continuity** during incidents

## 🏰 Multi-Layer Security Architecture

### Layer 1: Network Security

#### Bastion Host Architecture
```
Internet → Azure Firewall → Bastion Host → Management Cluster
                ↓
        Jump Box (Hardened VM)
        - Just-in-Time Access
        - Conditional Access Policies
        - Multi-Factor Authentication
        - Session Recording
```

**Implementation:**
- **Azure Bastion** with native RDP/SSH tunneling
- **No public IPs** on management cluster nodes
- **Private endpoints** for all Azure services
- **Network Security Groups** with minimal required ports
- **Azure Firewall** with application rules

```yaml
# Network Security Group - Management Cluster
apiVersion: network.azure.com/v1api20201101
kind: NetworkSecurityGroup
metadata:
  name: nsg-mgmt-cluster
spec:
  location: ${location}
  owner:
    name: ${management_resource_group}
  securityRules:
    - name: DenyAllInbound
      priority: 4096
      direction: Inbound
      access: Deny
      protocol: "*"
      sourcePortRange: "*"
      destinationPortRange: "*"
      sourceAddressPrefix: "*"
      destinationAddressPrefix: "*"
    - name: AllowBastionInbound
      priority: 1000
      direction: Inbound
      access: Allow
      protocol: Tcp
      sourcePortRange: "*"
      destinationPortRange: "22"
      sourceAddressPrefix: "10.0.1.0/24" # Bastion subnet
      destinationAddressPrefix: "*"
```

#### Private Cluster Configuration
```yaml
# Private AKS Management Cluster
apiServerAccessProfile:
  enablePrivateCluster: true
  enablePrivateClusterPublicFQDN: false
  privateDNSZone: "private.${location}.azmk8s.io"
  authorizedIPRanges: []  # No public access
```

### Layer 2: Identity & Access Management

#### Azure AD Integration
```yaml
# Strict AAD Integration
aadProfile:
  enableAzureRBAC: true
  managed: true
  adminGroupObjectIDs:
    - "${platform_admins_group_id}"     # Platform team only
    - "${security_admins_group_id}"     # Security team
  tenantID: "${tenant_id}"
disableLocalAccounts: true  # Force AAD authentication
```

#### RBAC Design Pattern

**Principle: Least Privilege with Role Segregation**

```yaml
---
# Platform Administrators (Full Access)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: "${platform_admins_group_id}"
  apiGroup: rbac.authorization.k8s.io

---
# GitOps Operators (Limited Admin)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gitops-operator
rules:
- apiGroups: [""]
  resources: ["namespaces", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["kustomize.toolkit.fluxcd.io"]
  resources: ["kustomizations"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["source.toolkit.fluxcd.io"]
  resources: ["gitrepositories", "helmrepositories"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

---
# Read-Only Observers
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: platform-observer
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/exec", "pods/attach", "pods/portforward"]
  verbs: [] # Explicitly deny
```

#### Service Account Security
```yaml
# Flux Service Account with Workload Identity
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-controller
  namespace: flux-system
  annotations:
    azure.workload.identity/client-id: "${flux_identity_client_id}"
automountServiceAccountToken: true

---
# Security Policy for Service Accounts
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: flux-restricted
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

### Layer 3: Git Repository Security

#### Repository Protection Strategy

**Azure DevOps Protection:**
```yaml
# ADO Branch Policies (via Azure DevOps API/Terraform)
branch_policies:
  main:
    require_pull_request: true
    required_reviewers:
      minimum_count: 2
      require_code_owner_review: true
      dismiss_stale_reviews: true
    required_status_checks:
      - "Security Scan"
      - "Policy Validation"
      - "Dry Run Deployment"
    restrict_pushes: true
    allowed_merge_types:
      - "squash"
    delete_branch_on_merge: true
```

**GitLab Protection:**
```yaml
# GitLab Push Rules
push_rules:
  commit_message_regex: "^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .{1,50}"
  deny_unsigned_commits: true
  member_check: true
  prevent_secrets: true
  reject_unsigned_commits: true

# GitLab Branch Protection
protected_branches:
  main:
    push_access_level: "no_access"
    merge_access_level: "maintainer"
    code_owner_approval_required: true
```

#### Code Ownership (CODEOWNERS)
```bash
# .github/CODEOWNERS or .gitlab/CODEOWNERS
# Global owners for all files
* @platform-team @security-team

# Critical infrastructure files require security team approval
/eng/azureserviceoperator-flux/ @platform-team @security-team @compliance-team
/docs/security/ @security-team @compliance-team
/.github/workflows/ @platform-team @security-team
/.gitlab-ci.yml @platform-team @security-team

# Management cluster specific
/eng/azureserviceoperator-flux/overlays/management/ @platform-leads @security-leads

# Environment specific - requires env owners
/eng/azureserviceoperator-flux/overlays/prod/ @platform-leads @prod-owners
/eng/azureserviceoperator-flux/overlays/dev/ @platform-team @dev-owners
```

#### Secret Management in Git
```yaml
# .gitignore - Prevent secret commits
*.key
*.pem
*.p12
*.pfx
.env
.env.*
**/secrets/
**/secret/
kubeconfig
**/values-secret.yaml

# Pre-commit hooks (pre-commit-config.yaml)
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

### Layer 4: CI/CD Pipeline Security

#### Azure DevOps Security
```yaml
# Azure Pipeline with Security Gates
trigger:
  branches:
    include:
    - main
    - develop
  paths:
    include:
    - eng/azureserviceoperator-flux/

variables:
  - group: management-cluster-secrets  # Restricted variable group

stages:
- stage: SecurityValidation
  jobs:
  - job: SecretScan
    steps:
    - task: GitLeaks@1
      displayName: 'Scan for secrets'

  - job: PolicyValidation
    steps:
    - script: |
        # Validate Kubernetes manifests
        kubectl apply --dry-run=server --validate=true -f eng/azureserviceoperator-flux/base/
      displayName: 'Validate Kubernetes manifests'

  - job: SecurityScan
    steps:
    - task: AzureKeyVault@1
      inputs:
        azureSubscription: 'management-cluster-connection'
        KeyVaultName: 'kv-security-tools'
        SecretsFilter: 'polaris-token'
    - script: |
        # Run Polaris security scan
        polaris audit --config polaris-config.yaml
      displayName: 'Security policy scan'

- stage: ManualApproval
  dependsOn: SecurityValidation
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: ApprovalGate
    environment: 'management-cluster-approval'
    strategy:
      runOnce:
        deploy:
          steps:
          - script: echo "Manual approval required for management cluster changes"
```

#### GitLab CI/CD Security
```yaml
# .gitlab-ci.yml
stages:
  - security
  - validation
  - approval
  - deploy

variables:
  SECURE_ANALYZERS_PREFIX: "registry.gitlab.com/security-products"

secret_detection:
  stage: security
  extends: .secret-analyzer
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

sast:
  stage: security
  extends: .sast
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

policy_validation:
  stage: validation
  image: alpine/k8s:latest
  script:
    - kubectl apply --dry-run=server --validate=true -f eng/azureserviceoperator-flux/base/
    - conftest verify --policy security-policies/ eng/azureserviceoperator-flux/base/
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

manual_approval:
  stage: approval
  script:
    - echo "Changes require manual approval"
  when: manual
  environment:
    name: management-cluster
    action: prepare
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

### Layer 5: Runtime Security

#### Pod Security Standards
```yaml
# Pod Security Standards - Restricted
apiVersion: v1
kind: Namespace
metadata:
  name: flux-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted

---
# Network Policies - Deny All by Default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: flux-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 443  # HTTPS only
    - protocol: TCP
      port: 53   # DNS
    - protocol: UDP
      port: 53   # DNS
```

#### OPA Gatekeeper Policies
```yaml
# Require specific labels on management resources
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: requiredlabels
spec:
  crd:
    spec:
      names:
        kind: RequiredLabels
      validation:
        properties:
          labels:
            type: array
            items:
              type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package requiredlabels

        violation[{"msg": msg}] {
          required := input.parameters.labels
          provided := input.review.object.metadata.labels
          missing := required[_]
          not provided[missing]
          msg := sprintf("Missing required label: %v", [missing])
        }

---
# Apply policy to management cluster resources
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequiredLabels
metadata:
  name: management-cluster-labels
spec:
  match:
    kinds:
      - apiGroups: ["containerservice.azure.com"]
        kinds: ["ManagedCluster"]
      - apiGroups: ["resources.azure.com"]
        kinds: ["ResourceGroup"]
  parameters:
    labels: ["environment", "managed-by", "security-level"]
```

### Layer 6: Monitoring & Auditing

#### Comprehensive Audit Logging
```yaml
# Azure Monitor Configuration
azureMonitorProfile:
  metrics:
    enabled: true
    kubeStateMetrics:
      metricLabelsAllowlist: "namespaces=[*]"
  containerInsights:
    enabled: true
    logAnalyticsWorkspaceResourceReference:
      armId: ${security_log_analytics_workspace}

# Audit Policy
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
  - group: "rbac.authorization.k8s.io"
    resources: ["*"]
  - group: "kustomize.toolkit.fluxcd.io"
    resources: ["*"]
  namespaces: ["flux-system", "azure-system"]
```

#### Security Monitoring
```yaml
# Prometheus Rules for Security Monitoring
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: management-cluster-security
spec:
  groups:
  - name: security.rules
    rules:
    - alert: UnauthorizedAPIAccess
      expr: increase(apiserver_audit_total{objectRef_resource="secrets"}[5m]) > 5
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Unusual secret access detected"

    - alert: FailedAuthentication
      expr: increase(apiserver_audit_total{verb="create",objectRef_resource="tokenreviews",code=~"4.."}[5m]) > 10
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "Multiple authentication failures"

    - alert: FluxReconciliationFailure
      expr: gotk_reconcile_condition{type="Ready",status="False"} == 1
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: "Flux reconciliation failing for {{ $labels.name }}"
```

### Layer 7: Incident Response

#### Break Glass Procedures
```yaml
# Emergency Access Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: emergency-access
  namespace: kube-system
  annotations:
    # Only activated during incidents
    emergency.platform/activated: "false"
    emergency.platform/activated-by: ""
    emergency.platform/activated-at: ""

---
# Emergency RBAC (normally disabled)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: emergency-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: emergency-access
  namespace: kube-system
```

#### Disaster Recovery
```bash
#!/bin/bash
# Management Cluster DR Script

# 1. Backup etcd
kubectl exec -n kube-system etcd-master -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /backup/etcd-snapshot-$(date +%Y%m%d%H%M%S).db

# 2. Backup Flux state
kubectl get gitrepositories,kustomizations -A -o yaml > flux-backup-$(date +%Y%m%d).yaml

# 3. Backup secrets (encrypted)
kubectl get secrets -A -o yaml | gpg --encrypt -r security@company.com > secrets-backup-$(date +%Y%m%d).gpg
```

## 🚨 Security Incident Playbook

### 1. Suspected Compromise Detection
```bash
# Immediate response checklist
1. Isolate the management cluster (network segmentation)
2. Disable all automated deployments
3. Capture forensic evidence
4. Rotate all credentials
5. Audit all recent changes
```

### 2. Repository Compromise
```bash
# Repository security incident
1. Disable all CI/CD pipelines
2. Lock all branches
3. Audit commit history for malicious changes
4. Force re-authentication for all users
5. Review access logs
```

## 🔒 Security Hardening Checklist

### Management Cluster
- [ ] Private cluster with no public access
- [ ] Azure RBAC enabled with strict groups
- [ ] Local accounts disabled
- [ ] Pod Security Standards enforced
- [ ] Network policies implemented
- [ ] OPA Gatekeeper policies active
- [ ] Audit logging to SIEM
- [ ] Vulnerability scanning enabled

### Repository Security
- [ ] Branch protection rules configured
- [ ] Required reviewers enforced
- [ ] Status checks mandatory
- [ ] Secret scanning enabled
- [ ] Signed commits required
- [ ] CODEOWNERS file maintained
- [ ] Pre-commit hooks active

### Access Control
- [ ] Just-in-time access implemented
- [ ] Multi-factor authentication required
- [ ] Conditional access policies
- [ ] Regular access reviews
- [ ] Privileged access workstations
- [ ] Session recording enabled

### Monitoring
- [ ] Security event monitoring
- [ ] Anomaly detection
- [ ] Failed authentication alerts
- [ ] Unauthorized access alerts
- [ ] Configuration drift detection
- [ ] Compliance reporting

## 📋 Regular Security Reviews

### Weekly
- Review access logs
- Check failed authentication attempts
- Validate active user sessions
- Monitor security alerts

### Monthly
- Access review for all users
- Update security policies
- Vulnerability assessment
- Backup validation

### Quarterly
- Penetration testing
- Security architecture review
- Disaster recovery testing
- Compliance audit

## 🎓 Security Training Requirements

### Platform Team
- Kubernetes security best practices
- GitOps security patterns
- Incident response procedures
- Secure coding practices

### All Users
- Security awareness training
- Phishing identification
- Password management
- Incident reporting

## 📞 Emergency Contacts

```yaml
# Emergency Response Team
platform_team:
  primary: "+1-XXX-XXX-XXXX"
  secondary: "platform-oncall@company.com"

security_team:
  primary: "+1-XXX-XXX-XXXX"
  secondary: "security-incident@company.com"

management:
  ciso: "ciso@company.com"
  platform_manager: "platform-mgr@company.com"
```

---

## 🔍 Conclusion

Management cluster security requires a **holistic approach** combining:
- **Technical controls** (RBAC, network security, monitoring)
- **Process controls** (code review, change management)
- **People controls** (training, access management)

The security model assumes **zero trust** - verify everything, trust nothing. Every access request, code change, and deployment must be authenticated, authorized, and audited.

Remember: **Security is not a destination, it's a journey**. Regularly review and update these controls as threats evolve.