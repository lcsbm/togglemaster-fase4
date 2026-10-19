# ── Roles de CI/CD com least-privilege ───────────────────────────────────────
#
# CICD-terraform-infra  → terraform.yml (criado fora do Terraform, permissões amplas)
# CICD-ecr-push         → 5 CI workflows de serviços (só ECR push)
# CICD-self-healing     → self-healing.yml (só eks:DescribeCluster + K8s RBAC)

locals {
  account_id  = "603727984890"
  github_oidc = "token.actions.githubusercontent.com"
}

# ── CICD-ecr-push ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "cicd_ecr_push" {
  name = "CICD-ecr-push"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${local.github_oidc}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc}:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Qualquer branch/tag do repositório pode fazer push de imagens
          "${local.github_oidc}:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "cicd_ecr_push" {
  name = "ecr-push-togglemaster"
  role = aws_iam_role.cicd_ecr_push.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken é account-level, não tem ARN de recurso
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${var.project}/*"
      }
    ]
  })
}

# ── CICD-self-healing ─────────────────────────────────────────────────────────
resource "aws_iam_role" "cicd_self_healing" {
  name = "CICD-self-healing"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${local.github_oidc}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc}:aud" = "sts.amazonaws.com"
          # Restrito a workflow_dispatch na main — não assume a partir de PRs ou branches
          "${local.github_oidc}:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "cicd_self_healing" {
  name = "eks-describe-cluster"
  role = aws_iam_role.cicd_self_healing.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = module.eks.cluster_arn
    }]
  })
}

output "cicd_ecr_push_role_arn" {
  value       = aws_iam_role.cicd_ecr_push.arn
  description = "Role ARN para os CI workflows de build/push de imagens"
}

output "cicd_self_healing_role_arn" {
  value       = aws_iam_role.cicd_self_healing.arn
  description = "Role ARN para o workflow de self-healing"
}
