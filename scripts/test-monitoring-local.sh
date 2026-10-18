#!/usr/bin/env bash
# Testa a stack de monitoramento localmente com kind.
# Uso: bash scripts/test-monitoring-local.sh

set -euo pipefail

CLUSTER_NAME="togglemaster-monitoring"
MONITORING_NS="monitoring"

log() { echo -e "\n\033[1;36m>>> $*\033[0m"; }
ok()  { echo -e "\033[1;32m✓  $*\033[0m"; }
err() { echo -e "\033[1;31m✗  $*\033[0m"; exit 1; }

# ── 1. Cluster kind ──────────────────────────────────────────────────────────
log "Criando cluster kind '$CLUSTER_NAME'..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  ok "Cluster já existe, reutilizando."
else
  kind create cluster --name "$CLUSTER_NAME" --wait 90s
  ok "Cluster criado."
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# ── 2. Helm repos ────────────────────────────────────────────────────────────
log "Adicionando Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana              https://grafana.github.io/helm-charts
helm repo update
ok "Repos atualizados."

# ── 3. Namespace ─────────────────────────────────────────────────────────────
log "Criando namespace $MONITORING_NS..."
kubectl create namespace "$MONITORING_NS" --dry-run=client -o yaml | kubectl apply -f -

# ── 4. kube-prometheus-stack ─────────────────────────────────────────────────
log "Instalando kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version 61.7.2 \
  --namespace "$MONITORING_NS" \
  --values gitops/monitoring/kube-prometheus-stack/values.yaml \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.storageSpec="" \
  --set alertmanager.alertmanagerSpec.storage="" \
  --timeout 5m \
  --wait
ok "kube-prometheus-stack instalado."

# ── 5. loki-stack ───────────────────────────────────────────────────────────
log "Instalando loki-stack..."
helm upgrade --install loki-stack \
  grafana/loki-stack \
  --version 2.10.2 \
  --namespace "$MONITORING_NS" \
  --values gitops/monitoring/loki/values.yaml \
  --set loki.persistence.enabled=false \
  --timeout 5m \
  --wait
ok "loki-stack instalado."

# ── 6. Validações ────────────────────────────────────────────────────────────
log "Validando pods em $MONITORING_NS..."
kubectl get pods -n "$MONITORING_NS"

RUNNING=$(kubectl get pods -n "$MONITORING_NS" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
TOTAL=$(kubectl get pods -n "$MONITORING_NS" --no-headers 2>/dev/null | wc -l)

echo ""
echo "Pods Running: $RUNNING / $TOTAL"

if [ "$RUNNING" -lt "$TOTAL" ]; then
  echo ""
  echo "Pods com problema:"
  kubectl get pods -n "$MONITORING_NS" --no-headers | grep -v Running || true
fi

# ── 7. Valida datasource Loki no Grafana ────────────────────────────────────
log "Verificando Grafana (port-forward temporário)..."
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n "$MONITORING_NS" &
PF_PID=$!
sleep 5

HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  -u admin:admin123 \
  http://localhost:3000/api/health 2>/dev/null || echo "000")

kill $PF_PID 2>/dev/null || true

if [ "$HTTP" = "200" ]; then
  ok "Grafana health: 200"
else
  err "Grafana health: $HTTP (esperado 200)"
fi

# ── 8. Valida Prometheus ─────────────────────────────────────────────────────
log "Verificando Prometheus..."
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n "$MONITORING_NS" &
PF_PID=$!
sleep 4

PROM=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:9090/-/healthy 2>/dev/null || echo "000")

kill $PF_PID 2>/dev/null || true

if [ "$PROM" = "200" ]; then
  ok "Prometheus healthy: 200"
else
  err "Prometheus health: $PROM (esperado 200)"
fi

# ── 9. Valida Loki ───────────────────────────────────────────────────────────
log "Verificando Loki..."
kubectl port-forward svc/loki-stack 3100:3100 -n "$MONITORING_NS" &
PF_PID=$!
sleep 4

LOKI=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:3100/ready 2>/dev/null || echo "000")

kill $PF_PID 2>/dev/null || true

if [ "$LOKI" = "200" ]; then
  ok "Loki ready: 200"
else
  err "Loki ready: $LOKI (esperado 200)"
fi

# ── Resultado ────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo " Validação local concluída com sucesso!"
echo " Pods: $RUNNING/$TOTAL Running"
echo " Grafana  : http://localhost:3000  (admin/admin123 via port-forward)"
echo " Prometheus: http://localhost:9090 (via port-forward)"
echo " Loki      : http://localhost:3100 (via port-forward)"
echo ""
echo " Para destruir o cluster local:"
echo "   kind delete cluster --name $CLUSTER_NAME"
echo "════════════════════════════════════════"
