# ── EKS access entry para CICD-self-healing ──────────────────────────────────
# Cria a identidade Kubernetes para o role IAM.
# Nenhuma access policy da AWS é associada — permissões vêm apenas do RBAC abaixo.

resource "aws_eks_access_entry" "cicd_self_healing" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = aws_iam_role.cicd_self_healing.arn
  kubernetes_groups = []
  # username limpo facilita o RoleBinding — sem ARN dinâmico de sessão
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
