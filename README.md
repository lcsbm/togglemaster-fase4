# ToggleMaster - Fase 4: Observabilidade

**FIAP POSTECH - DevOps e Arquitetura Cloud**
**RM 373161 - Lucas Santana Bezerra de Melo**

Fase 4 do Tech Challenge. Adiciona observabilidade completa à plataforma de feature flags ToggleMaster: métricas, logs centralizados, distributed tracing, alertas inteligentes e self-healing automatizado.

A base das Fases 1, 2 e 3 (microsserviços containerizados, Terraform, CI/CD com DevSecOps e GitOps com ArgoCD) está integralmente presente neste repositório.

---

## Arquitetura

```
Cliente
  └── nginx Ingress (ELB)
        ├── /auth/*         --> auth-service        :8001 (Go)
        ├── /flags/*        --> flag-service         :8002 (Python)
        ├── /rules/*        --> targeting-service    :8003 (Python)
        ├── /evaluate/*     --> evaluation-service   :8004 (Go)
        └── /analytics/*    --> analytics-service    :8005 (Python)

Observabilidade (namespace: monitoring)

  Microsserviços --[OTLP gRPC]--> OTel Collector
                                      ├── Prometheus  (métricas)
                                      ├── Loki        (logs)
                                      └── New Relic   (APM / traces)

  Grafana <-- Prometheus + Loki

Alertas & Self-Healing

  Grafana Alert --[webhook]--> GitHub Action (self-healing.yml)
                  ├── PagerDuty  (incidente)
                  └── Discord    (ChatOps)
```

---

## Stack

| Camada | Tecnologia |
|---|---|
| Infraestrutura | AWS EKS (us-east-1), RDS PostgreSQL, ElastiCache Redis, SQS, Secrets Manager |
| IaC | Terraform 1.12 |
| GitOps | ArgoCD (auto-sync, prune, selfHeal) |
| CI/CD | GitHub Actions + Trivy (DevSecOps) |
| Métricas | Prometheus + kube-state-metrics + node-exporter |
| Logs | Loki + Promtail |
| Visualização | Grafana (kube-prometheus-stack v61.7.2) |
| Telemetria | OpenTelemetry Collector 0.104.0 (OTLP gRPC receiver) |
| APM / Tracing | New Relic (Distributed Tracing + Service Map) |
| Incidentes | PagerDuty (Events API V2) |
| ChatOps | Discord webhook |
| Self-Healing | GitHub Actions (`self-healing.yml`) disparado via Grafana webhook |
| Autoscaling | HPA (evaluation-service, CPU 70%) + KEDA (analytics-service, SQS) |
| Secrets | External Secrets Operator --> AWS Secrets Manager |

---

## Estrutura do repositório

```
togglemaster-fase4/
├── services/
│   ├── auth-service/           # Go - autenticação e API keys
│   ├── evaluation-service/     # Go - avaliação de flags (Redis + SQS)
│   ├── flag-service/           # Python - CRUD de feature flags
│   ├── targeting-service/      # Python - regras de targeting
│   └── analytics-service/      # Python - consumidor SQS
├── gitops/
│   ├── */                      # Manifests K8s dos 5 serviços
│   └── monitoring/             # Prometheus, Loki, Grafana, OTel Collector
├── infra/terraform/            # Infraestrutura completa AWS
└── .github/workflows/
    ├── ci-*.yml                # CI para cada microsserviço
    ├── terraform.yml           # Plan / Apply (aprovação manual)
    ├── terraform-destroy.yml   # Destroy com confirmação manual
    └── self-healing.yml        # Rollout restart via workflow_dispatch
```

---

## IAM Roles (GitHub OIDC)

| Role | Usado por | Permissões |
|---|---|---|
| `CICD-terraform-infra` | terraform.yml | Ampla (criar/destruir infra) |
| `CICD-ecr-push` | ci-*.yml (5 serviços) | ECR push em `togglemaster/*` |
| `CICD-self-healing` | self-healing.yml | `eks:DescribeCluster` + K8s RBAC namespace-scoped |

---

## Pré-requisitos

- AWS CLI configurado (`aws configure`)
- `kubectl`, `terraform` e `helm` instalados
- Conta New Relic (free tier) com License Key
- Conta PagerDuty (free tier) com Integration Key (Events API V2)
- Discord webhook URL
- GitHub PAT com escopo `workflow`

---

## Setup

### 1. Secrets no AWS Secrets Manager

```bash
# New Relic
aws secretsmanager create-secret \
  --name togglemaster/new-relic \
  --secret-string '{"license_key":"<sua-key>"}' \
  --region us-east-1

# PagerDuty
aws secretsmanager create-secret \
  --name togglemaster/pagerduty \
  --secret-string '{"integration_key":"<sua-key>"}' \
  --region us-east-1

# Discord
aws secretsmanager create-secret \
  --name togglemaster/discord \
  --secret-string '{"webhook_url":"<sua-url>"}' \
  --region us-east-1

# GitHub PAT (escopo: workflow)
aws secretsmanager create-secret \
  --name togglemaster/github-pat \
  --secret-string '{"token":"ghp_..."}' \
  --region us-east-1
```

### 2. Infraestrutura

```bash
# Via GitHub Actions (recomendado)
# Actions --> Terraform CI/CD --> Run workflow
# O apply aguarda aprovação manual em "Review deployments"

# Ou localmente
cd infra/terraform
terraform init
terraform apply
```

### 3. Configurar kubectl

```bash
aws eks update-kubeconfig --name togglemaster --region us-east-1
kubectl get nodes
```

### 4. ArgoCD sincroniza automaticamente

```bash
kubectl get applications -n argocd
# togglemaster   Synced   Healthy
```

---

## Fluxo de alertas

```
Grafana detecta taxa 5xx > 5% por 1 minuto
  │
  ├── PagerDuty  --> incidente aberto automaticamente
  ├── Discord    --> mensagem no canal #alerts
  └── GitHub Actions (self-healing.yml)
        └── kubectl rollout restart deployment/auth-service -n togglemaster
```

---

## Custo estimado

> Destrua imediatamente após a avaliação.
> Custo estimado se mantido 24/7: ~$250/mês.

```bash
# Via GitHub Actions
# Actions --> Terraform Destroy --> Run workflow --> digite DESTROY

# Ou localmente
cd infra/terraform
terraform destroy
```

---

## Progresso

Consulte [PLANEJAMENTO-FASE4.md](PLANEJAMENTO-FASE4.md) para o acompanhamento detalhado por etapa.
