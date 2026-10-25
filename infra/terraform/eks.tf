module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.project
  cluster_version = "1.36"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Endpoint público restrito — acesso via kubectl de IPs conhecidos
  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = var.eks_public_access_cidrs
  enable_cluster_creator_admin_permissions = true

  # Evita conflito de "already exists" no apply/destroy
  create_cloudwatch_log_group = false

  # Prefix Delegation: aumenta o limite de pods por nó de 17 para ~110 (t3.medium)
  cluster_addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    # EBS CSI Driver: obrigatório no EKS 1.27+ (provisioner in-tree kubernetes.io/aws-ebs removido)
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    workers = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.eks_node_type]

      min_size     = var.eks_min_nodes
      max_size     = var.eks_max_nodes
      desired_size = var.eks_desired_nodes

      # Disco mínimo para economizar
      disk_size = 20

      # Informa ao kubelet o limite correto de pods para prefix delegation
      # Sem isso, o kubelet usa o default calculado para IPs individuais (17 no t3.medium)
      # Com prefix delegation ativo no VPC CNI, o limite real é 110 pods por nó
      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content = jsonencode({
            apiVersion = "node.eks.aws/v1alpha1"
            kind       = "NodeConfig"
            spec = {
              kubelet = {
                config = {
                  maxPods = 110
                }
              }
            }
          })
        }
      ]
    }
  }

  access_entries = {
    admin = {
      principal_arn = var.eks_admin_iam_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  cluster_timeouts = {
    create = "30m"
    update = "60m"
    delete = "60m"
  }

  tags = local.common_tags
}
