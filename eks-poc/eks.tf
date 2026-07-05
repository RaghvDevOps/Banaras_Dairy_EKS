module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name = "banaras-Dairy-EKS"
  cluster_version = "1.30"
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.public_subnets
  cluster_endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true
  eks_managed_node_groups = {
    general = {
      desired_size = 2
      max_size = 3
      min_size = 1
      instance_types = ["t3.medium"]
      capacity_type = "ON_DEMAND"
      # POC shortcut: node role gets ALB Controller permissions directly
      # (instead of proper IRSA). See alb_controller_iam.tf for why.
      iam_role_additional_policies = {
        AWSLoadBalancerController = aws_iam_policy.alb_controller.arn
      }
    }
  }
}
