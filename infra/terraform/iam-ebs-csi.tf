# ── IRSA para o EBS CSI Driver ────────────────────────────────────────────────
# O addon aws-ebs-csi-driver precisa de permissões IAM para criar/deletar/montar
# volumes EBS. Usamos IRSA para que apenas o service account do driver tenha acesso.
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project}-ebs-csi-role"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

output "ebs_csi_role_arn" {
  description = "ARN da role IRSA do EBS CSI Driver"
  value       = module.ebs_csi_irsa.iam_role_arn
}
