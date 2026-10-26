# test-crash-alert.ps1 -- Provoca CrashLoopBackOff no auth-service para disparar alerta
#
# Uso: powershell -ExecutionPolicy Bypass -File .\scripts\test-crash-alert.ps1
#
# Fluxo esperado:
#   1. Captura os pods alvo UMA VEZ no inicio (snapshot)
#   2. Loop mata apenas esses pods -> CrashLoopBackOff
#   3. Grafana detecta 0 replicas disponiveis -> dispara alerta (avaliacao 1m)
#   4. self-healing-relay aciona workflow -> kubectl rollout restart
#   5. Novos pods sobem com nomes diferentes (fora do alvo)
#   6. Script detecta pods novos saudaveis e encerra automaticamente

$namespace  = "togglemaster"
$appLabel   = "app=auth-service"
$round      = 0
$healed     = $false

function Show-PodStatus {
    param([string]$ns, [string]$label)
    kubectl get pods -n $ns -l $label --no-headers -o wide 2>$null
}

function Test-SelfHealing {
    param([string[]]$targets, [string]$ns, [string]$label)
    $lines = kubectl get pods -n $ns -l $label --no-headers 2>$null
    $healedPods = @()
    foreach ($line in $lines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 3) { continue }
        $name   = $parts[0]
        $ready  = $parts[1]
        $status = $parts[2]
        if ($ready -eq '1/1' -and $status -eq 'Running' -and $targets -notcontains $name) {
            $healedPods += $name
        }
    }
    return $healedPods
}

Write-Host "=== Capturando pods alvo (snapshot inicial) ===" -ForegroundColor Yellow

$raw = kubectl get pods -n $namespace -l $appLabel -o jsonpath="{.items[*].metadata.name}" 2>$null
$targetPods = ($raw -split '\s+') | Where-Object { $_ -ne '' }

if ($targetPods.Count -eq 0) {
    Write-Host "Nenhum pod encontrado para $appLabel em $namespace. Encerrando." -ForegroundColor Red
    exit 1
}

Write-Host "Pods alvo fixados:" -ForegroundColor Cyan
foreach ($p in $targetPods) { Write-Host "  $p" }
Write-Host ""
Write-Host "O script matara apenas esses pods. Quando o self-healing fizer rollout" -ForegroundColor DarkGray
Write-Host "restart, novos pods (nomes diferentes) nao serao afetados." -ForegroundColor DarkGray
Write-Host ""
Write-Host "=== Iniciando loop de crash (para automaticamente ao detectar self-healing) ===" -ForegroundColor Yellow
Write-Host ""

try {
    while ($true) {
        $round++

        foreach ($pod in $targetPods) {
            kubectl exec -n $namespace $pod -- kill 1 2>$null
            Write-Host "Round $round -- killed $pod"
        }

        # A cada 10 rounds mostra status completo
        if (($round % 10) -eq 0) {
            Write-Host ""
            Write-Host "--- Status (round $round) ---" -ForegroundColor Cyan
            Show-PodStatus -ns $namespace -label $appLabel
            Write-Host ""
        }

        # Verifica self-healing apos round 10 (tempo para alerta + rollout)
        if ($round -ge 10) {
            $healedPods = Test-SelfHealing -targets $targetPods -ns $namespace -label $appLabel
            if ($healedPods.Count -gt 0) {
                Write-Host ""
                Write-Host "=== Self-healing detectado! ===" -ForegroundColor Green
                Write-Host "Novos pods saudaveis (nao fazem parte do alvo original):" -ForegroundColor Green
                foreach ($h in $healedPods) { Write-Host "  $h" -ForegroundColor Green }
                $healed = $true
                break
            }
        }

        Start-Sleep -Seconds 1
    }
} catch {
    # Ctrl+C
} finally {
    Write-Host ""
    if ($healed) {
        Write-Host "=== Encerrado automaticamente -- self-healing bem-sucedido no round $round ===" -ForegroundColor Green
    } else {
        Write-Host "=== Loop encerrado manualmente no round $round ===" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "--- Status final dos pods ---" -ForegroundColor Cyan
    kubectl get pods -n $namespace -l $appLabel
    Write-Host ""
    Write-Host "Aguardando deployment estabilizar (timeout 5min)..."
    kubectl rollout status deployment/auth-service -n $namespace --timeout=300s
    Write-Host ""
    kubectl get pods -n $namespace -l $appLabel
}
