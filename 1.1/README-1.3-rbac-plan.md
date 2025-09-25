# Story 1.3: Cross-Subscription RBAC Implementation Plan

## Overview

This document outlines the structured plan for implementing User Assigned Managed Identity (UAMI) with workload identity federation to replace the current Service Principal (SPN) with Contributor role access. The goal is to implement fine-grained, secure cross-subscription RBAC for Azure Service Operator (ASO).

## Phase 1: Current State Analysis & Requirements Gathering

### 1.1 Audit Current SPN Configuration
- [ ] Document current SPN permissions and scope assignments
- [ ] Identify which subscriptions/management groups currently have Contributor access
- [ ] Map current resource provisioning patterns and dependencies
- [ ] Document any existing automation or tooling dependencies on current SPN

### 1.2 Management Group Structure Analysis
- [ ] Document current management group hierarchy for each environment
- [ ] Identify which clusters/subscriptions are under each management group
- [ ] Determine optimal management group level for UAMI permission assignment
- [ ] Validate management group permissions inheritance patterns

## Phase 2: Permission Requirements & Security Design

### 2.1 Fine-Tune Permission Requirements
- [ ] Analyze actual resource operations performed by ASO
- [ ] Compare proposed actions list against current SPN usage patterns
- [ ] Identify any missing permissions for:
  - Resource tagging and metadata management
  - Azure Policy compliance operations
  - Cost management and billing operations
  - Diagnostic settings and monitoring setup
- [ ] Define NotActions to exclude unnecessary Contributor permissions

### 2.2 UAMI Architecture Design
- [ ] Design multi-UAMI strategy per environment (primary + backup)
- [ ] Define federated identity credential configuration for each UAMI
- [ ] Plan service account mapping for workload identity federation
- [ ] Design failover/fallback procedures between UAMIs

### 2.3 Security Controls Validation
- [ ] Define audit logging requirements for RBAC actions
- [ ] Plan conditional access policy integration
- [ ] Design permission validation and monitoring automation
- [ ] Define regular access review procedures

## Phase 3: SRE Collaboration & Approval Process

### 3.1 SRE Requirements Gathering
- [ ] Schedule discovery session with SRE team to discuss:
  - Current operational procedures that may be affected
  - Monitoring and alerting requirements for new identity system
  - Incident response procedures for authentication failures
  - Rollback procedures and emergency access requirements

### 3.2 Approval & Compliance Process
- [ ] Identify required approvals for:
  - Management group level RBAC assignments
  - New custom role definition creation
  - Workload identity federation setup
  - Cross-subscription resource access patterns
- [ ] Document security review requirements
- [ ] Plan change management and deployment approvals

## Phase 4: POC Implementation Planning

### 4.1 POC Scope Definition
- [ ] Select target subscriptions for POC (same environment, different subscription)
- [ ] Define minimal test scenario:
  - Create resource group
  - Deploy basic AKS cluster
  - Create associated networking resources
  - Set up monitoring resources
- [ ] Plan POC success criteria and validation tests

### 4.2 POC Implementation Strategy
- [ ] Create POC-specific UAMI with limited scope
- [ ] Implement federated identity credentials for test service account
- [ ] Deploy ASO configuration pointing to POC UAMI
- [ ] Create automation scripts for POC validation

### 4.3 POC Risk Mitigation
- [ ] Plan isolation of POC resources from production
- [ ] Define rollback procedures for POC
- [ ] Set up monitoring for POC authentication and provisioning operations

## Phase 5: Production Implementation Planning

### 5.1 Phased Rollout Strategy
- [ ] Plan environment-by-environment rollout (dev → staging → prod)
- [ ] Define coexistence period with current SPN approach
- [ ] Plan gradual migration of workloads to new UAMI system
- [ ] Define criteria for retiring old SPN credentials

### 5.2 Monitoring & Operations
- [ ] Implement UAMI health monitoring
- [ ] Set up alerting for authentication failures
- [ ] Create operational runbooks for UAMI management
- [ ] Plan regular permission auditing automation

## Proposed Permission Actions

Based on initial analysis, the UAMI will need these actions (to be refined during Phase 2.1):

```json
{
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
  ]
}
```

## Immediate Next Steps (This Week)

1. **Audit Current State** - Document existing SPN configuration and management group structure
2. **SRE Discovery Call** - Schedule session to understand operational requirements and constraints
3. **Permission Analysis** - Compare proposed actions against actual ASO resource operations
4. **POC Planning** - Define specific POC scope and success criteria with SRE team

## Key Questions to Resolve

1. **Management Group Scope**: Which management group level provides optimal balance of security and operational simplicity?
2. **Permission Granularity**: Are there additional Azure resource types that ASO needs to manage beyond the initial list?
3. **Operational Impact**: What current automation or monitoring depends on the existing SPN that would need updating?
4. **Approval Timeline**: What's the expected timeline for getting management group level RBAC changes approved?
5. **Failover Strategy**: How quickly can you switch between primary and backup UAMI in case of issues?

## Success Criteria

- [ ] UAMI successfully provisions cross-subscription resources
- [ ] Permissions follow principle of least privilege
- [ ] Zero downtime migration from current SPN approach
- [ ] Comprehensive monitoring and alerting in place
- [ ] SRE team comfortable with operational procedures
- [ ] All compliance and approval requirements met

## Risk Mitigation

- **Authentication Failures**: Backup UAMI ready for immediate failover
- **Permission Gaps**: Thorough testing in POC environment before production
- **Operational Impact**: Extensive SRE collaboration and runbook development
- **Rollback Plan**: Ability to revert to current SPN approach if needed