# Official AWS Load Balancer Controller IAM policy (from the project's own repo).
# POC SHORTCUT: attached directly to the node group's IAM role, so any pod on
# any node can call these AWS APIs via the EC2 instance role (IMDS creds).
#
# Proper production pattern = IRSA (IAM Roles for Service Accounts): only the
# controller's own Kubernetes ServiceAccount gets this policy, scoped via
# OIDC federation, not every pod on the node. That's on the POC learning plan
# as a follow-up (see docs/EKS_POC_Learning_Plan.md).
resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy-banaras-poc"
  description = "Permissions for the AWS Load Balancer Controller to manage ALBs/NLBs for banaras-Dairy-EKS"
  policy      = file("${path.module}/alb_controller_iam_policy.json")
}
