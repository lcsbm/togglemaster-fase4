# ToggleMaster - Fase 4: Observabilidade

**FIAP POSTECH - DevOps e Arquitetura Cloud** -
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
                                      ├── Loki        (logs via Promtail)
                                      └── New Relic   (APM / traces)

  Grafana <-- Prometheus + Loki

Alertas & Self-Healing

  Grafana Alert --[webhook]--> self-healing-relay (monitoring)
                  │                  └── GitHub Actions self-healing.yml
                  │                        └── kubectl rollout restart
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
| Self-Healing | self-healing-relay → GitHub Actions (`self-healing.yml`) |
| Autoscaling | HPA (evaluation-service, CPU 70%) + KEDA (analytics-service, SQS) |
| Secrets | External Secrets Operator → AWS Secrets Manager |

---

## Estrutura do repositório

```
togglemaster-fase4/
├── services/
│   ├── auth-service/           # Go — autenticação e API keys
│   ├── evaluation-service/     # Go — avaliação de flags (Redis + SQS)
│   ├── flag-service/           # Python — CRUD de feature flags
│   ├── targeting-service/      # Python — regras de targeting
│   └── analytics-service/      # Python — consumidor SQS
├── gitops/
│   ├── */                      # Manifests K8s dos 5 serviços + ExternalSecrets
│   ├── argocd/                 # ExternalSecret para argocd-secret
│   ├── self-healing-relay/     # Deployment do relay webhook → GitHub Actions
│   └── monitoring/
│       ├── kube-prometheus-stack/  # Prometheus + Grafana + Alertmanager
│       ├── loki/                   # Loki + Promtail
│       ├── otel-collector/         # OTel Collector + ExternalSecret New Relic
│       └── grafana/                # ExternalSecrets + Dashboard ConfigMap
├── infra/terraform/            # Infraestrutura completa AWS
├── scripts/
│   ├── test-alerts.sh          # Testa relay, Discord e E2E (bash)
│   └── test-crash-alert.ps1    # Força CrashLoopBackOff para disparar alertas (PowerShell)
└── .github/workflows/
    ├── ci-*.yml                # CI para cada microsserviço (build, test, Trivy, push ECR)
    ├── terraform.yml           # Plan / Apply (aprovação manual)
    ├── terraform-destroy.yml   # Destroy com confirmação manual (timeout 6h, retry automático)
    └── self-healing.yml        # Rollout restart via workflow_dispatch (OIDC)
```

---

## IAM Roles (GitHub OIDC)

| Role | Usado por | Permissões |
|---|---|---|
| `CICD-terraform-infra` | terraform.yml, terraform-destroy.yml | Ampla (criar/destruir infra) |
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

# ArgoCD (bcrypt hash da senha admin)
aws secretsmanager create-secret \
  --name togglemaster/argocd \
  --secret-string '{"admin_password":"$2a$10$...","server_secretkey":"<random>"}' \
  --region us-east-1

# Grafana
aws secretsmanager create-secret \
  --name togglemaster/grafana \
  --secret-string '{"admin":"<senha>"}' \
  --region us-east-1
```

### 2. Infraestrutura

```bash
# Via GitHub Actions (recomendado)
# Actions → Terraform CI/CD → Run workflow
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
# NAME                    SYNC     HEALTH
# togglemaster            Synced   Healthy
# kube-prometheus-stack   Synced   Healthy
# loki-stack              Synced   Healthy
# otel-collector          Synced   Healthy
```

---

## Fluxo de alertas e self-healing

```
1. auth-service fica sem réplicas disponíveis
2. Grafana avalia a regra a cada 1 minuto (for: 0m → dispara imediato)
3. Grafana envia webhook para self-healing-relay (monitoring)
4. Relay filtra status=firing e dispara workflow_dispatch → self-healing.yml
5. GitHub Actions executa: kubectl rollout restart deployment/auth-service
6. Em paralelo: PagerDuty abre incidente + Discord recebe notificação
```

### Testar manualmente

```powershell
# Força CrashLoopBackOff em loop (PowerShell) — Ctrl+C para parar
.\scripts\test-crash-alert.ps1
```

```bash
# Testar relay diretamente (sem downtime)
bash scripts/test-alerts.sh relay

# Testar apenas notificação Discord
bash scripts/test-alerts.sh discord

# Testar fluxo E2E completo
bash scripts/test-alerts.sh e2e
```

---

## Custo estimado

> Destrua imediatamente após a avaliação.
> Custo estimado se mantido 24/7: ~$250/mês.

```bash
# Via GitHub Actions
# Actions → Terraform Destroy → Run workflow → digite DESTROY
```

---

## Progresso

Consulte [PLANEJAMENTO-FASE4.md](PLANEJAMENTO-FASE4.md) para o acompanhamento detalhado por etapa.
