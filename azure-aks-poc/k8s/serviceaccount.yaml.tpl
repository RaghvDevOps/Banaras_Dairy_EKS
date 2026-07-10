# Template, not applied directly -- deploy.sh substitutes __BACKEND_CLIENT_ID__
# with the real Managed Identity Client ID (a Terraform output) before
# applying. Kept as a template because that ID only exists AFTER `terraform
# apply` runs, so it can't be hardcoded here.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: banaras-backend-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: __BACKEND_CLIENT_ID__
  labels:
    azure.workload.identity/use: "true"
