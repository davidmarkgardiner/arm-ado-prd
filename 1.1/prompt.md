We will begin working on 1.3. 

Okay, so in Azure, you have the things called management groups. All the clusters in each environment are attached to a management group. 

the uami should be assinged permissons at management scope level 
I guess we need to do is have a look at seeing exactly what access this identity would need. 

I think the preference would be to create a couple of UAMIs per environment and have them federated. We can have a backup account that we could revert to if this starts having authentication issues for any reason. 

This is more secure as there's no secrets exposed and it's all done via Role Buying Federation and service accounts. 

Questions. 
What permissions would the identity need? 
We need to cross-check this against what's in place today. 
today we use spn that has contribtor role but this needs fine tuned.

Do a POC on this UAMI creating a cluster plus associated resources in another swci (same env)

These are the data actions that I could think of at the moment that it would definitely need. 

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

I need to work with our Site Reliability Engineering team to understand the scope, what we need to implement, how we need to implement it, if there are any approvals we need to go through, and how we can POC this out. 

Just help me come up with a plan, in a structured format, so we can work through this and answer the questions that aren't perfectly clear at the moment. 