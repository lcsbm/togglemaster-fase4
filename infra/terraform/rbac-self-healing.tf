# ── EKS access entry para CICD-self-healing ──────────────────────────────────
# O role IAM é criado manualmente (fora do Terraform).
# O data source lê o ARN para criar o access entry e o RBAC.

data "aws_iam_role" "cicd_self_healing" {
  name = "CICD-self-healing"
}

resource "aws_eks_access_entry" "cicd_self_healing" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = data.aws_iam_role.cicd_self_healing.arn
  kubernetes_groups = []
  # Username limpo facilita o RoleBinding — sem ARN dinâmico de sessão
  user_name = "cicd-self-healing"
  type      = "STANDARD"

  tags = local.common_tags
}

# ── K8s RBAC: Role mínimo no namespace togglemaster ──────────────────────────
# kubectl rollout restart  → PATCH em deployments
# kubectl rollout status   → GET + WATCH em deployments

resource "kubernetes_role" "self_healing" {
  metadata {
    name      = "self-healing"
    namespace = var.project
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "patch"]
  }
}

resource "kubernetes_role_binding" "self_healing" {
  metadata {
    name      = "self-healing"
    namespace = var.project
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.self_healing.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "cicd-self-healing"
    api_group = "rbac.authorization.k8s.io"
  }
}
