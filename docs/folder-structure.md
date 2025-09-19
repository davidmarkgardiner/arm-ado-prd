> folder structure
## Worker Cluster Manifest's

```yaml

  eng/

    azureserviceoperator/

      base/

        configmap/

          # Contains ConfigMaps with key-value pairs for variable interpolation (e.g., AKS names, locations,, VNET etc.)

        cluster/

          # Cluster resource definitions - deploys worker clusters

        identity/

          # Identity resources sets up Federation with UAMI

        flux/

          # Flux configuration resources sets up core and config flux sync for apps + ns

        maintenanceconfiguration/

          # Maintenance window and related configs

        monitoring/

          # This sets up the prometheus grafana integration, can be used for dcr, actiongroups, metricsalerts etc

        kustomization.yaml

          resources:

            - configmap

            - cluster

            - identity

            - flux

            - maintenanceconfiguration

            - monitoring

 

```

## Management Cluster Manifest's

```yaml

      managementcluster/

        rbac/

          # RBAC policies for the management cluster

        configmap/

          # ConfigMaps for management cluster-specific variables

        cluster/

          # Cluster resource definitions deploys management cluster

        identity/

          # Identity resources sets up Federation with UAMI

        flux/

          # Flux configuration resources will deploy worker clusters and associated yaml

        maintenanceconfiguration/

          # Maintenance window configs

        monitoring/

          # This sets up the prometheus grafana integration, can be used for dcr, actiongroups, metricsalerts etc

        kustomization.yaml

          resources:

            - rbac

            - configmap

            - cluster

            - identity

            - flux

            - maintenanceconfiguration

            - monitoring

```
