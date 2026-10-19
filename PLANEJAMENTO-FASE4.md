# Planejamento — ToggleMaster Fase 4

**FIAP POSTECH — DevOps e Arquitetura Cloud**
**RM 373161 — Lucas Sousa Beraldi Moreira**

> Documento de acompanhamento de progresso. Atualizar os checkboxes conforme cada item for concluído.

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
| 6 | Self-Healing (GitHub Action) | ⬜ Pendente |
| 7 | Terraform apply + validação E2E | ⬜ Pendente |

---

## Etapa 0 — Migração da base da Fase 3

- [x] Copiar `services/` (5 microsserviços)
- [x] Copiar `gitops/` (manifests K8s)
- [x] Copiar `infra/terraform/` (IaC)
- [x] Copiar `.github/workflows/` (CI/CD)
- [x] Atualizar `github_repo` → `lcsbm/togglemaster-fase4`
- [x] Atualizar `backend.tf` → state key `fase4/terraform.tfstate`
- [x] Push para `https://github.com/lcsbm/togglemaster-fase4`

---

## Etapa 1 — Stack de monitoramento no GitOps ✅

> Objetivo: Prometheus, Loki e Grafana rodando no cluster via ArgoCD.
> Localização: `gitops/monitoring/`

- [x] `gitops/monitoring/namespace.yaml` — namespace `monitoring`
- [x] `gitops/monitoring/kube-prometheus-stack/` — ArgoCD Application + values.yaml (v61.7.2)
- [x] `gitops/monitoring/loki/` — ArgoCD Application + values.yaml (loki-stack v2.10.2)
- [x] Grafana embutido no kube-prometheus-stack com sidecar de dashboards
- [x] Grafana pré-configurado com datasource Loki
- [x] Validação local (kind): 8/8 pods Running
- [x] Validação local: Grafana 200, Prometheus 200, Loki 200
- [x] PR mergeado: `feat/monitoring-stack`

**Dashboard customizado deve exibir (Etapa 5):**
- [ ] Uso de CPU e memória dos nós do cluster
- [ ] Taxa de requisições HTTP por microsserviço
- [ ] Taxa de erros HTTP 5xx por microsserviço
- [ ] Painel de logs em tempo real (Loki datasource)

---

## Etapa 2 — OTel Collector 🔄

> Objetivo: hub central de telemetria — recebe dados dos microsserviços e roteia para Prometheus, Loki e New Relic.
> Localização: `gitops/monitoring/otel-collector/`

- [x] `configmap.yaml` — pipeline OTLP receiver → batch processor → exporters (traces + metrics + logs)
- [x] `deployment.yaml` — Deployment otel/opentelemetry-collector-contrib:0.104.0
- [x] `service.yaml` — Service ClusterIP expondo 4317 (gRPC), 4318 (HTTP), 8889 (metrics)
- [x] `serviceaccount.yaml` — ServiceAccount dedicado
- [x] `servicemonitor.yaml` — ServiceMonitor para Prometheus scrape
- [x] `externalsecret.yaml` — ExternalSecret para New Relic License Key
- [x] `application.yaml` — ArgoCD Application
- [x] Exporter Prometheus configurado (porta 8889)
- [x] Exporter Loki configurado
- [x] Exporter OTLP/gRPC para New Relic (`otlp.nr-data.net:4317`)
- [ ] Validar no cluster AWS: pod Running
- [ ] Validar: microsserviço enviando spans visíveis no New Relic

**Variável de ambiente nos microsserviços:**
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.monitoring.svc.cluster.local:4317
OTEL_SERVICE_NAME=<nome-do-servico>
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

---

## Etapa 3 — Instrumentação dos microsserviços

> Objetivo: adicionar bibliotecas OTel ao código-fonte de cada serviço para gerar traces, métricas e logs estruturados.

### auth-service (Go)
- [ ] Adicionar deps: `go.opentelemetry.io/otel`, `otlpgrpc`, `otelhttp`
- [ ] Inicializar TracerProvider em `main.go`
- [ ] Instrumentar rotas HTTP com `otelhttp.NewHandler`
- [ ] Atualizar `go.mod` / `go.sum`
- [ ] Validar: traces aparecem no New Relic com service name `auth-service`

### evaluation-service (Go)
- [ ] Mesmas deps de OTel que auth-service
- [ ] Instrumentar rotas HTTP
- [ ] Adicionar span manual para chamada ao Redis (cache hit/miss)
- [ ] Adicionar span manual para envio ao SQS
- [ ] Validar: trace E2E mostrando caminho de `/evaluate`

### flag-service (Python)
- [ ] Adicionar deps: `opentelemetry-sdk`, `opentelemetry-exporter-otlp`, `opentelemetry-instrumentation-flask`
- [ ] Auto-instrumentar Flask com `FlaskInstrumentor`
- [ ] Atualizar `requirements.txt`
- [ ] Validar: traces no New Relic com service name `flag-service`

### targeting-service (Python)
- [ ] Mesmas deps de OTel que flag-service
- [ ] Auto-instrumentar Flask
- [ ] Validar: traces no New Relic com service name `targeting-service`

### analytics-service (Python)
- [ ] Mesmas deps de OTel que flag-service
- [ ] Instrumentar consumer loop do SQS (span por mensagem processada)
- [ ] Validar: traces no New Relic com service name `analytics-service`

### Dockerfiles / ConfigMaps
- [ ] Adicionar `OTEL_EXPORTER_OTLP_ENDPOINT` nos ConfigMaps de cada serviço (`gitops/*/configmap.yaml`)
- [ ] Adicionar `OTEL_SERVICE_NAME` e `OTEL_RESOURCE_ATTRIBUTES` nos ConfigMaps
- [ ] Rebuild das imagens via CI/CD (push → ArgoCD sync automático)

---

## Etapa 4 — APM New Relic ✅

> Objetivo: Service Map dos 5 serviços + Distributed Tracing visível no painel.

- [x] Criar conta New Relic free tier (US region)
- [x] Obter License Key (INGEST - LICENSE)
- [x] Adicionar License Key no AWS Secrets Manager (`togglemaster/new-relic`) como JSON `{"license_key":"..."}`)
- [x] ExternalSecret criado em `gitops/monitoring/otel-collector/externalsecret.yaml`
- [x] OTel Collector configurado com exporter `otlp/newrelic` → `otlp.nr-data.net:4317`
- [ ] Validar no cluster AWS: painel New Relic > APM > Services mostrando os 5 serviços
- [ ] Validar: Service Map com dependências visíveis
- [ ] Validar: trace distribuído de `/evaluate` (auth → evaluation → redis/sqs)
- [ ] Screenshot do Service Map para entregável

---

## Etapa 5 — Alertas + PagerDuty + Discord

> Objetivo: alerta ativo quando taxa de erros 5xx > 5%, incidente no PagerDuty e notificação no Discord.

### Alerta no Grafana
- [ ] Criar Alert Rule: `rate(http_requests_total{status=~"5.."}[5m]) > 0.05`
  - Serviço alvo: `auth-service` (ou todos os serviços)
  - For: 1 minuto
  - Labels: `severity=critical`, `service=auth-service`
- [ ] Provisionar regra via ConfigMap no GitOps (`gitops/monitoring/grafana/alertrule.yaml`)

### PagerDuty
- [ ] Criar conta PagerDuty free tier
- [ ] Criar Service com integration "Grafana"
- [ ] Obter Integration Key
- [ ] Adicionar Integration Key no AWS Secrets Manager (`togglemaster/pagerduty`)
- [ ] Configurar Contact Point no Grafana (PagerDuty)
- [ ] Configurar Notification Policy: todos os alertas `severity=critical` → PagerDuty
- [ ] Validar: incidente aberto automaticamente no PagerDuty quando alerta dispara

### Discord
- [ ] Criar canal `#alerts-togglemaster` no Discord (ou usar existente)
- [ ] Criar Webhook no Discord
- [ ] Adicionar Webhook URL no AWS Secrets Manager (`togglemaster/discord`)
- [ ] Configurar Contact Point no Grafana (Discord)
- [ ] Configurar Notification Policy: todos os alertas → Discord
- [ ] Validar: mensagem de alerta chegando no canal Discord

---

## Etapa 6 — Self-Healing (GitHub Action via webhook)

> Objetivo: quando um alerta dispara no Grafana, o sistema reage automaticamente executando `kubectl rollout restart`.

### GitHub Action
- [ ] Criar `.github/workflows/self-healing.yml`
  - Trigger: `workflow_dispatch` com inputs `service` e `namespace`
  - Step 1: configure AWS credentials (OIDC)
  - Step 2: `aws eks update-kubeconfig`
  - Step 3: `kubectl rollout restart deployment/${{ inputs.service }} -n ${{ inputs.namespace }}`
  - Step 4: `kubectl rollout status deployment/${{ inputs.service }} -n ${{ inputs.namespace }}`
- [ ] Criar Personal Access Token (PAT) com escopo `workflow`
- [ ] Adicionar PAT no AWS Secrets Manager (`togglemaster/github-pat`)

### Webhook do Grafana → GitHub Action
- [ ] Criar Contact Point no Grafana do tipo "Webhook"
  - URL: `https://api.github.com/repos/lcsbm/togglemaster-fase4/actions/workflows/self-healing.yml/dispatches`
  - Headers: `Authorization: Bearer <PAT>`, `Accept: application/vnd.github+json`
  - Body: `{"ref":"main","inputs":{"service":"auth-service","namespace":"togglemaster"}}`
- [ ] Incluir este Contact Point na Notification Policy do alerta
- [ ] Validar: alerta dispara → GitHub Action executa → pod reinicia automaticamente
- [ ] Screenshot do workflow executado para entregável

---

## Etapa 7 — Terraform apply + validação E2E

> Objetivo: cluster completo no ar com toda a stack de observabilidade operacional.

- [ ] `terraform apply` via pipeline (PR → plan → aprovação → apply)
- [ ] Validar: 9+ pods Running em `togglemaster`
- [ ] Validar: pods Running em `monitoring` (Prometheus, Loki, Grafana, OTel Collector)
- [ ] Validar: ArgoCD Applications Synced + Healthy
- [ ] Validar: Dashboard Grafana acessível (port-forward ou Ingress)
- [ ] Validar: Service Map no New Relic com 5 serviços
- [ ] Executar fluxo E2E (criar flag → criar regra → avaliar → verificar trace no New Relic)
- [ ] Causar falha proposital (parar RDS do flag-service) e gravar vídeo de:
  - [ ] Alerta disparando no Grafana
  - [ ] Incidente abrindo no PagerDuty
  - [ ] Notificação chegando no Discord
  - [ ] Self-Healing executando no GitHub Actions
  - [ ] Pod reiniciando (kubectl rollout status)

---

## Entregáveis finais

- [ ] Repositório GitHub com todo o código
- [ ] Vídeo de demonstração (até 25 min)
- [ ] Relatório PDF com evidências visuais:
  - [ ] Print do Dashboard Grafana customizado
  - [ ] Print de Trace distribuído no New Relic
  - [ ] Print da notificação no Discord
  - [ ] Print do log de execução do Self-Healing (GitHub Actions)
  - [ ] Justificativa técnica: New Relic vs Datadog, PagerDuty vs OpsGenie

---

## Decisões de arquitetura

| Decisão | Escolha | Justificativa |
|---|---|---|
| APM | **New Relic** | Suporte nativo OTLP sem agente proprietário; free tier 100 GB/mês sem cartão |
| Incident Management | **PagerDuty** | Integração nativa com Grafana; free tier funcional |
| ChatOps | **Discord** | Webhook simples de configurar; sem necessidade de app workspace |
| OTel Collector | **otel/opentelemetry-collector-contrib** | Hub único para Prometheus + Loki + New Relic |
| Self-Healing trigger | **Grafana webhook → GitHub Action** | Sem infra extra; reutiliza OIDC já configurado |

---

## Referências

- [OpenTelemetry Go](https://opentelemetry.io/docs/languages/go/)
- [OpenTelemetry Python](https://opentelemetry.io/docs/languages/python/)
- [OTel Collector Config](https://opentelemetry.io/docs/collector/configuration/)
- [New Relic OTLP endpoint](https://docs.newrelic.com/docs/more-integrations/open-source-telemetry-integrations/opentelemetry/opentelemetry-introduction/)
- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)
- [kube-prometheus-stack Helm](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki Stack Helm](https://grafana.com/docs/loki/latest/setup/install/helm/)
