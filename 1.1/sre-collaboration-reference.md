# SRE Collaboration Reference: Cross-Subscription RBAC Modernization

## Overview

This document serves as a reference for the SRE team collaboration session on implementing User Assigned Managed Identity (UAMI) with workload identity federation to replace the current Service Principal (SPN) per subscription model.

## Current State Analysis

### SPN-per-Subscription Model

**Architecture:**
- One Service Principal per SWCI (subscription)
- Each SPN has Contributor role access
- Deployment scope limited to subscription boundary
- Isolated resource provisioning

**Current Challenges:**
- **Over-privileged Access:** Contributor role grants excessive permissions
- **Management Complexity:** Multiple SPNs to manage, rotate, and monitor
- **Limited Cross-Subscription Capability:** Cannot efficiently manage resources spanning subscriptions
- **Security Concerns:** Stored secrets and broad permissions

## Proposed Architecture

### Unified UAMI Model

**Core Components:**
- **Primary UAMI:** Main identity for cross-subscription resource provisioning
- **Backup UAMI:** Secondary identity for failover scenarios
- **Management Group Scope:** RBAC assigned at management group level
- **Workload Identity Federation:** No stored secrets, OIDC-based authentication

### Security Controls Architecture

```
Developer Request → GitOps Repository (PR) → SRE Approval → Flux Sync → ASO Controller → Cross-Subscription Deployment
```

**Management Cluster Protection:**
- Private cluster with bastion access only
- Azure AD PIM for breakglass access
- Gatekeeper policies enforcing resource constraints
- Comprehensive audit logging

**UAMI Security Features:**
- Workload identity federation (no secrets)
- Custom role with minimal required permissions
- Conditional access policies
- Regular automated permission audits

## Permission Model Comparison

### Current: Contributor Role
```json
{
  "RoleName": "Contributor",
  "Scope": "Subscription",
  "Permissions": "Broad access to create, modify, delete most Azure resources"
}
```

### Proposed: Custom ASO Role
```json
{
  "RoleName": "ASO Cross-Subscription Deployer",
  "Scope": "Management Group",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/*",
    "Microsoft.ContainerService/managedClusters/*",
    "Microsoft.ContainerService/managedClusters/agentPools/*",
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.Network/virtualNetworks/subnets/*",
    "Microsoft.Network/networkSecurityGroups/*",
    "Microsoft.Network/privateDnsZones/*",
    "Microsoft.ManagedIdentity/userAssignedIdentities/*",
    "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/*",
    "Microsoft.OperationalInsights/workspaces/*",
    "Microsoft.Insights/dataCollectionRules/*",
    "Microsoft.Insights/actionGroups/*",
    "Microsoft.AlertsManagement/prometheusRuleGroups/*"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": []
}
```

## Implementation Roadmap

### Phase 1: Analysis & Planning (Week 1-2)
- [ ] Audit current SPN usage patterns and dependencies
- [ ] Document management group structure and access patterns
- [ ] Map operational procedures that depend on current SPN model
- [ ] Identify approval processes and compliance requirements

### Phase 2: POC Development (Week 3-4)
- [ ] Create POC-specific UAMI with limited scope
- [ ] Implement federated identity credentials
- [ ] Deploy test ASO configuration
- [ ] Validate cross-subscription resource creation
- [ ] Test monitoring and alerting systems

### Phase 3: Production Rollout (Week 5-8)
- [ ] Environment-by-environment deployment (dev → staging → prod)
- [ ] Gradual migration from SPN to UAMI
- [ ] Comprehensive monitoring and validation
- [ ] Documentation and runbook updates

## SRE Collaboration Points

### Critical Questions for SRE Team

**Operational Impact:**
1. What current operational procedures depend on the per-subscription SPN model?
2. How do you currently monitor SPN health, usage, and rotation?
3. What automation or tooling would be affected by this change?
4. What's your experience with Azure workload identity and potential issues?

**Implementation Requirements:**
1. What approval process is needed for management group level RBAC changes?
2. What's the typical timeline for getting these approvals?
3. What compliance or audit requirements must be considered?
4. What monitoring/alerting should be implemented for the new system?

**Risk Management:**
1. What are your concerns about the proposed architecture?
2. How should we handle emergency access scenarios?
3. What rollback procedures would you want in place?
4. What validation should occur before each phase?

### Proposed SRE Involvement

**Policy Review & Approval:**
- Final sign-off on Gatekeeper policies before deployment to management cluster
- Review and approval of custom RBAC role definitions
- Validation of conditional access policies

**Monitoring & Alerting Design:**
- Collaborate on dashboard design for UAMI health and usage
- Define alerting thresholds for authentication failures
- Set up monitoring for cross-subscription resource provisioning

**Operational Procedures:**
- Joint development of incident response runbooks
- Creation of troubleshooting guides for common issues
- Documentation of emergency access procedures

**POC Validation:**
- Participate in POC testing and validation phases
- Review POC results and provide feedback
- Sign-off on production readiness criteria

## POC Scope Definition

### Test Scenario
- **Objective:** Validate cross-subscription resource provisioning using UAMI
- **Environment:** Same management group, different subscription than management cluster
- **Resources to Create:**
  - Resource group in target subscription
  - Basic AKS cluster with system node pool
  - Virtual network and subnet (if cross-subscription networking)
  - Log Analytics workspace for monitoring

### Success Criteria
- [ ] UAMI successfully authenticates via workload identity federation
- [ ] Cross-subscription resource group creation successful
- [ ] AKS cluster deployment completes without errors
- [ ] Network resources created with proper configuration
- [ ] Monitoring resources deployed and configured
- [ ] All operations logged and auditable
- [ ] No permission escalation beyond defined custom role

### Risk Mitigation
- **Isolation:** POC resources completely isolated from production
- **Rollback:** Ability to quickly delete all POC resources
- **Monitoring:** Enhanced logging during POC to capture any issues
- **Fallback:** Current SPN approach remains available during POC

## Technical Requirements

### Management Cluster Requirements
- **Network:** Private cluster with bastion host access
- **Identity:** Azure AD integration with PIM for emergency access
- **Policy Enforcement:** Gatekeeper with custom constraints
- **GitOps:** Flux v2 for declarative deployments
- **Monitoring:** Comprehensive logging and alerting

### UAMI Configuration
- **Federation:** OIDC issuer URL from management cluster
- **Subject Pattern:** `system:serviceaccount:azure-service-operator-system:azureserviceoperator-default`
- **Audience:** `api://AzureADTokenExchange`
- **Scope:** Management group level assignment

### Security Validation
- **Access Testing:** Automated validation of cross-subscription permissions
- **Boundary Testing:** Verification that UAMI cannot exceed defined permissions
- **Audit Validation:** Confirmation that all actions are properly logged
- **Incident Response:** Testing of emergency access and rollback procedures

## Questions for Discussion

### Priority 1 (Must Resolve Before POC)
1. What approval process and timeline is needed for management group RBAC changes?
2. Are there any compliance requirements that would block this approach?
3. What monitoring/alerting is essential for the new system?
4. What are the rollback requirements if authentication fails?

### Priority 2 (Resolve During POC)
1. Are the proposed permissions sufficient for all ASO operations?
2. What additional operational procedures need to be documented?
3. How should we handle permission boundary testing?
4. What validation should occur before production rollout?

### Priority 3 (Resolve Before Production)
1. What regular access review procedures should be implemented?
2. How should we handle future permission changes or additions?
3. What disaster recovery procedures are needed?
4. What training is needed for team members?

## Next Steps

### This Week
- [ ] Finalize POC scope with SRE team
- [ ] Begin documentation of current SPN usage patterns
- [ ] Start approval process for management group RBAC changes
- [ ] Set up POC environment and UAMI creation

### Following Week
- [ ] Complete POC implementation
- [ ] Conduct validation testing with SRE team
- [ ] Document lessons learned and refine approach
- [ ] Plan production rollout timeline

## Contact Information

**Project Team:**
- Platform Engineer: [Your Name]
- SRE Team Lead: [To be filled]
- Security Contact: [To be filled]

**Meeting Schedule:**
- Weekly check-ins during implementation
- Ad-hoc calls for urgent issues or blockers
- Formal review at end of each phase

---

*This document will be updated throughout the implementation process to reflect decisions made and lessons learned.*