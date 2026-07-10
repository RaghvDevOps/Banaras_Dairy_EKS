# Template -- deploy.sh substitutes the placeholders below with real
# Terraform outputs before applying. This is the CSI driver config that
# fetches the 4 DB secrets from Key Vault and materializes them as the
# `db-credentials` Kubernetes Secret consumed by backend.yaml / postgres.yaml.
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: banaras-backend-kv-secrets
  namespace: default
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: "__BACKEND_CLIENT_ID__"
    keyvaultName: "__KEY_VAULT_NAME__"
    tenantId: "__TENANT_ID__"
    objects: |
      array:
        - |
          objectName: db-password
          objectType: secret
        - |
          objectName: postgres-user
          objectType: secret
        - |
          objectName: postgres-db
          objectType: secret
        - |
          objectName: recovery-db
          objectType: secret
  secretObjects:
    - secretName: db-credentials
      type: Opaque
      data:
        - objectName: db-password
          key: POSTGRES_PASSWORD
        - objectName: postgres-user
          key: POSTGRES_USER
        - objectName: postgres-db
          key: POSTGRES_DB
        - objectName: recovery-db
          key: RECOVERY_DB
