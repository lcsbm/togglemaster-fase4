# Planejamento — ToggleMaster Fase 4

**FIAP POSTECH — DevOps e Arquitetura Cloud** -
**RM 373161 — Lucas Santana Bezerra de Melo**

> Documento de acompanhamento de progresso.

---

## Progresso geral

| Etapa | Descrição | Status |
|---|---|---|
| 0 | Migração da base da Fase 3 | ✅ Concluído |
| 1 | Stack de monitoramento no GitOps | ✅ Concluído |
| 2 | OTel Collector | ✅ Concluído |
| 3 | Instrumentação dos microsserviços | ✅ Concluído |
| 4 | APM — New Relic | ✅ Concluído |
| 5 | Alertas + PagerDuty + Discord | ✅ Concluído |
| 6 | Self-Healing (GitHub Action) | ✅ Concluído |
| 7 | Gravação + Evidências | ⬜ Pendente |

---

## Etapa 0 — Migração da base da Fase 3 ✅

- [x] Copiar `services/` (5 microsserviços)
- [x] Copiar `gitops/` (manifests K8s)
- [x] Copiar `infra/terraform/` (IaC)
- [x] Copiar `.github/workflows/` (CI/CD)
- [x] Atualizar `github_repo` → `lcsbm/togglemaster-fase4`
- [x] Atualizar `backend.tf` → state key `fase4/terraform.tfstate`
- [x] Push para `https://github.com/lcsbm/togglemaster-fase4`

---

## Etapa 1 — Stack de monitoramento no GitOps ✅

- [x] `gitops/monitoring/namespace.yaml` — namespace `monitoring`
- [x] `gitops/monitoring/kube-prometheus-stack/` — ArgoCD Application + values.yaml (v61.7.2)
- [x] `gitops/monitoring/loki/` — ArgoCD Application + values.yaml (loki-stack v2.10.2)
- [x] Grafana embutido no kube-prometheus-stack com sidecar de dashboards
- [x] Grafana pré-configurado com datasource Prometheus e Loki
- [x] Dashboard customizado provisionado via ConfigMap (`gitops/monitoring/grafana/dashboard-togglemaster.yaml`)
  - [x] CPU e memória dos nós do cluster
  - [x] Taxa de requisições HTTP por microsserviço
  - [x] Taxa de erros HTTP 5xx por microsserviço
  - [x] Painel de logs em tempo real (Loki datasource)
- [x] Credenciais Grafana via ExternalSecret → AWS Secrets Manager
- [x] ArgoCD: kube-prometheus-stack Synced + Healthy
- [x] ArgoCD: loki-stack Synced + Healthy
- [x] Drift cosmético ignorado via `ignoreDifferences` (CRDs, webhooks caBundle, DaemonSet/Deployment)

---

## Etapa 2 — OTel Collector ✅

- [x] `configmap.yaml` — pipeline OTLP receiver → batch processor → exporters
- [x] `deployment.yaml` — otel/opentelemetry-collector-contrib:0.104.0
- [x] `service.yaml` — ClusterIP 4317 (gRPC), 4318 (HTTP), 8889 (metrics)
- [x] `serviceaccount.yaml`
- [x] `servicemonitor.yaml` — ServiceMonitor para Prometheus scrape
- [x] `externalsecret.yaml` — New Relic License Key via AWS SM
- [x] `application.yaml` — ArgoCD Application (com exclude do self-management loop)
- [x] Exporter Prometheus (porta 8889)
- [x] Exporter Loki
- [x] Exporter OTLP/gRPC para New Relic (`otlp.nr-data.net:4317`)
- [x] ArgoCD: otel-collector Synced + Healthy

---

## Etapa 3 — Instrumentação dos microsserviços ✅

### auth-service (Go)
- [x] Deps OTel: `go.opentelemetry.io/otel`, `otlpgrpc`, `otelhttp`
- [x] TracerProvider inicializado em `main.go`
- [x] Rotas HTTP instrumentadas com `otelhttp.NewHandler`

### evaluation-service (Go)
- [x] Deps OTel iguais ao auth-service
- [x] Rotas HTTP instrumentadas
- [x] Span manual para Redis (cache hit/miss)
- [x] Span manual para envio SQS

### flag-service (Python)
- [x] Deps: `opentelemetry-sdk`, `opentelemetry-exporter-otlp`, `opentelemetry-instrumentation-flask`
- [x] Auto-instrumentação Flask com `FlaskInstrumentor`

### targeting-service (Python)
- [x] Mesmas deps do flag-service
- [x] Auto-instrumentação Flask

### analytics-service (Python)
- [x] Mesmas deps do flag-service
- [x] Span por mensagem processada no consumer SQS

### ConfigMaps
- [x] `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES` em todos os serviços

---

## Etapa 4 — APM New Relic ✅

- [x] Conta New Relic free tier (US region)
- [x] License Key no AWS Secrets Manager (`togglemaster/new-relic`)
- [x] ExternalSecret em `gitops/monitoring/otel-collector/externalsecret.yaml`
- [x] OTel Collector com exporter `otlp/newrelic` → `otlp.nr-data.net:4317`

---

## Etapa 5 — Alertas + PagerDuty + Discord ✅

- [x] Alert Rule provisionada via `grafana.alerting.rules.yaml`
  - Métrica: `kube_deployment_status_replicas_available{deployment="auth-service"} < 1`
  - For: 0m, interval: 1m, noDataState: Alerting
  - Labels: `severity=critical`, `team=platform`
- [x] Contact Point PagerDuty (Events API V2) — provisionado via values.yaml
- [x] Contact Point Discord (webhook) — provisionado via values.yaml
- [x] Contact Point Self-Healing (webhook → relay interno) — provisionado via values.yaml
- [x] `manageAlerts: false` no datasource Loki (elimina erro "Failed to load Loki alert rules")
- [x] Notification Policy: Discord (root) → PagerDuty + Self-Healing (severity=critical)
- [x] PagerDuty Integration Key no AWS SM (`togglemaster/pagerduty`)
- [x] Discord Webhook URL no AWS SM (`togglemaster/discord`)

---

## Etapa 6 — Self-Healing ✅

- [x] `.github/workflows/self-healing.yml` — `workflow_dispatch` → `kubectl rollout restart`
- [x] IAM Role `CICD-self-healing` com OIDC
- [x] GitHub PAT (escopo `workflow`) no AWS SM (`togglemaster/github-pat`)
- [x] `self-healing-relay` deployment no namespace `monitoring`
  - Recebe webhook do Grafana (HTTP POST)
  - Filtra `"status": "firing"`
  - Dispara `workflow_dispatch` para `self-healing.yml` via GitHub API
- [x] ExternalSecret `grafana-github-pat` injetando PAT no relay
- [x] Scripts de teste em `scripts/`:
  - `test-alerts.sh` — testa relay, Discord e fluxo E2E (bash)
  - `test-crash-alert.ps1` — mata PID 1 em loop para forçar CrashLoopBackOff (PowerShell)

---

## Etapa 7 — Gravação + Evidências ⬜

> Objetivo: subir o cluster, executar os testes, gravar o vídeo e capturar as evidências.

### Pré-gravação (infraestrutura)
- [ ] Terraform apply via GitHub Actions (aguardar aprovação)
- [ ] Confirmar: todos os pods Running em `togglemaster` e `monitoring`
- [ ] Confirmar: ArgoCD — todos os apps Synced + Healthy
- [ ] Confirmar: Grafana acessível e dashboard carregando dados reais

### Evidências New Relic
- [ ] Verificar APM > Services: 5 serviços aparecendo
- [ ] Screenshot do Service Map
- [ ] Screenshot de um trace distribuído de `/evaluate`

### Evidências alertas e self-healing
- [ ] Rodar `.\scripts\test-crash-alert.ps1` para forçar CrashLoopBackOff
- [ ] Screenshot da notificação chegando no Discord
- [ ] Screenshot do incidente aberto no PagerDuty
- [ ] Screenshot do workflow `self-healing.yml` executando no GitHub Actions
- [ ] Screenshot do `kubectl rollout status` mostrando recovery

### Gravação do vídeo (até 25 min)
- [ ] Mostrar arquitetura geral (README / diagrama)
- [ ] Mostrar cluster rodando (ArgoCD, pods)
- [ ] Mostrar Dashboard Grafana com métricas reais
- [ ] Demonstrar fluxo de alerta E2E (crash → Discord → PagerDuty → self-healing → recovery)
- [ ] Mostrar New Relic Service Map + trace distribuído
- [ ] Mostrar CI/CD pipeline (GitHub Actions)

### Entregáveis finais
- [ ] Repositório GitHub público com todo o código
- [ ] Vídeo de demonstração enviado
- [ ] Relatório PDF com evidências visuais

---

## Decisões de arquitetura

| Decisão | Escolha | Justificativa |
|---|---|---|
| APM | **New Relic** | Suporte nativo OTLP sem agente proprietário; free tier 100 GB/mês sem cartão |
| Incident Management | **PagerDuty** | Integração nativa com Grafana; free tier funcional |
| ChatOps | **Discord** | Webhook simples de configurar; sem necessidade de app workspace |
| OTel Collector | **otel/opentelemetry-collector-contrib** | Hub único para Prometheus + Loki + New Relic |
| Self-Healing trigger | **Grafana webhook → self-healing-relay → GitHub Action** | Sem infra extra; reutiliza OIDC já configurado |

---

## Referências

- [OpenTelemetry Go](https://opentelemetry.io/docs/languages/go/)
- [OpenTelemetry Python](https://opentelemetry.io/docs/languages/python/)
- [OTel Collector Config](https://opentelemetry.io/docs/collector/configuration/)
- [New Relic OTLP endpoint](https://docs.newrelic.com/docs/more-integrations/open-source-telemetry-integrations/opentelemetry/opentelemetry-introduction/)
- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)
- [kube-prometheus-stack Helm](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki Stack Helm](https://grafana.com/docs/loki/latest/setup/install/helm/)
