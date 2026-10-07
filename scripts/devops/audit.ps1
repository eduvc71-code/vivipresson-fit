# VIVIPREFIT - Auditoria del Proyecto (v4 - final)
param(
  [switch]$Json,
  [string]$Root = "D:\ViviProfit"
)

$ErrorActionPreference = "Continue"
[ int ]$PassCount = 0
[ int ]$WarnCount = 0
[ int ]$FailCount = 0
$Issues = New-Object System.Collections.ArrayList
$StartTs = Get-Date

function Section { param([string]$m) Write-Host ""; Write-Host "== $m ==" -ForegroundColor Magenta }
function Info { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Cyan }

function Pass {
  param([string]$m)
  Write-Host "  [PASS] $m" -ForegroundColor Green
  $global:PassCount = $global:PassCount + 1
}

function Warn {
  param([string]$m)
  Write-Host "  [WARN] $m" -ForegroundColor Yellow
  $global:WarnCount = $global:WarnCount + 1
  [void]$global:Issues.Add("WARN|$m")
}

function Fail {
  param([string]$m)
  Write-Host "  [FAIL] $m" -ForegroundColor Red
  $global:FailCount = $global:FailCount + 1
  [void]$global:Issues.Add("FAIL|$m")
}

function CheckFile {
  param([string]$Rel, [double]$MinKB)
  $full = Join-Path $Root $Rel
  if (-not (Test-Path $full)) { Fail "FALTA: $Rel"; return $false }
  $kb = [math]::Round((Get-Item $full).Length / 1KB, 2)
  if ($kb -lt $MinKB) { Warn "$Rel pequeno ($kb KB, min $MinKB KB)"; return $false }
  Pass "$Rel ($kb KB)"
  return $true
}

function CheckFolder {
  param([string]$Rel)
  $full = Join-Path $Root $Rel
  if (Test-Path $full -PathType Container) { Pass "Carpeta OK: $Rel"; return $true }
  Fail "FALTA carpeta: $Rel"
  return $false
}

function CheckPatterns {
  param([string]$Rel, [array]$Patterns, [switch]$Any)
  $full = Join-Path $Root $Rel
  if (-not (Test-Path $full)) { Fail "No existe $Rel"; return }
  $content = Get-Content $full -Raw
  if ($Any) {
    foreach ($p in $Patterns) {
      if ($content -match [regex]::Escape($p)) { Pass "$Rel contiene: $p"; return }
    }
    Fail "$Rel no contiene ninguno de: $($Patterns -join ' | ')"
  }
  else {
    $missing = 0
    foreach ($p in $Patterns) {
      if ($content -match [regex]::Escape($p)) { $global:PassCount = $global:PassCount + 1 }
      else { Warn "$Rel no contiene: $p"; $missing++ }
    }
    if ($missing -eq 0) { Pass "$Rel tiene todos los patrones ($($Patterns.Count))" }
  }
}

Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  VIVIPREFIT - AUDITORIA DEL PROYECTO" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Info "Raiz: $Root"
Info "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Section "1. RAIZ"
if (-not (Test-Path $Root)) { Fail "No existe: $Root"; exit 1 }
Pass "Directorio raiz existe"

Section "2. CARPETAS"
$folders = @(
  "frontend", "frontend/assets", "frontend/assets/img",
  "supabase", "supabase/functions", "supabase/functions/stripe-webhook",
  "supabase/functions/bunny-token", "supabase/migrations",
  "database", "scripts", "scripts/devops",
  "docs", "media", "media/videos", "media/pdfs",
  "logs", ".github", ".github/workflows", ".vscode"
)
foreach ($f in $folders) { CheckFolder $f | Out-Null }

Section "3. FRONTEND"
CheckFile "frontend/index.html" 30 | Out-Null

Section "4. BASE DE DATOS"
$schemaOk = CheckFile "database/schema.sql" 5
if ($schemaOk) {
  CheckPatterns "database/schema.sql" @(
    "public.profiles", "public.landing_config", "public.membership_content",
    "ROW LEVEL SECURITY", "handle_new_user", "is_admin",
    "has_active_subscription", "CREATE POLICY", "CREATE TRIGGER", "storage.buckets"
  )
}

Section "5. EDGE FUNCTIONS"
$stripeOk = CheckFile "supabase/functions/stripe-webhook/index.ts" 2
$bunnyOk = CheckFile "supabase/functions/bunny-token/index.ts" 1.5
CheckFile "supabase/functions/deno.json" 0.1 | Out-Null
CheckFile "supabase/config.toml" 0.2 | Out-Null

if ($stripeOk) {
  CheckPatterns "supabase/functions/stripe-webhook/index.ts" @(
    "stripe-signature", "constructEventAsync", "checkout.session.completed",
    "customer.subscription.created", "customer.subscription.updated",
    "customer.subscription.deleted", "invoice.paid", "plan_status"
  )
}

if ($bunnyOk) {
  CheckPatterns "supabase/functions/bunny-token/index.ts" @(
    "crypto.subtle.digest", "BUNNY_STREAM_TOKEN_KEY", "embedUrl", "hlsUrl", "plan_status"
  )
  CheckPatterns "supabase/functions/bunny-token/index.ts" @(
    "has_active_subscription", "plan_status", "is_admin"
  ) -Any
}

Section "6. CONFIGURACION RAIZ"
CheckFile ".gitignore"   0.1 | Out-Null
CheckFile ".env.example" 0.2 | Out-Null
CheckFile "README.md"    0.5 | Out-Null
CheckFile "package.json" 0.3 | Out-Null

$pkgC = Get-Content (Join-Path $Root "package.json") -Raw -ErrorAction SilentlyContinue
if ($pkgC) {
  try { $null = $pkgC | ConvertFrom-Json; Pass "package.json es JSON valido" }
  catch { Fail "package.json invalido" }
}

Section "7. .env"
$envPath = Join-Path $Root ".env"
if (Test-Path $envPath) {
  $envC = Get-Content $envPath -Raw
  $vars = @("SUPABASE_URL", "SUPABASE_ANON_KEY", "STRIPE_SECRET_KEY", "BUNNY_STREAM_LIBRARY_ID")
  $missing = @()
  foreach ($v in $vars) {
    if ($envC -notmatch "(?m)^\s*$v\s*=\s*\S+") { $missing += $v }
  }
  if ($missing.Count -eq 0) { Pass ".env con variables criticas" }
  else { Warn ".env sin: $($missing -join ', ')" }
}
else {
  Warn "No existe .env (Copy-Item .env.example .env)"
}

Section "8. DEPENDENCIAS SISTEMA"
foreach ($cmd in @("node", "npm", "git", "supabase", "psql")) {
  $c = Get-Command $cmd -ErrorAction SilentlyContinue
  if ($c) {
    try { $v = & $cmd --version 2>&1 | Select-Object -First 1; Pass "$cmd : $v" }
    catch { Pass "$cmd instalado" }
  }
  else {
    if ($cmd -eq "psql") { Warn "$cmd no encontrado (opcional)" }
    else { Warn "$cmd no encontrado en PATH" }
  }
}

Section "9. NODE_MODULES"
if (Test-Path (Join-Path $Root "node_modules")) { Pass "node_modules existe" }
else { Warn "node_modules no existe (npm install)" }

Section "10. VALIDACION HTML"
$htmlPath = Join-Path $Root "frontend/index.html"
if (Test-Path $htmlPath) {
  $html = Get-Content $htmlPath -Raw
  $checks = @(
    '<!DOCTYPE html>', 'lang="es"', 'id="adminPanel"', 'id="userDashboard"',
    'id="classesContainer"', 'id="resourcesContainer"', 'id="authModal"',
    'createClient', 'handleAuthSubmit', 'toggleAdminPanel',
    'landing_config', 'membership_content',
    'enableImageEditing', 'enableTextEditing',
    'supabase-js@2', 'bunny-token'
  )
  $ok = 0
  foreach ($p in $checks) { if ($html -match [regex]::Escape($p)) { $ok++ } }
  if ($ok -ge ($checks.Count - 2)) { Pass "HTML: $ok / $($checks.Count)" }
  elseif ($ok -ge ($checks.Count / 2)) { Warn "HTML: $ok / $($checks.Count)" }
  else { Fail "HTML: solo $ok / $($checks.Count)" }

  $ids = [regex]::Matches($html, 'id="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
  $dupes = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
  if ($dupes) { Warn "IDs duplicados: $($dupes.Name -join ', ')" }
  else { Pass "Sin IDs duplicados" }
}

Section "11. VALIDACION SQL"
if ($schemaOk) {
  $sql = Get-Content (Join-Path $Root "database/schema.sql") -Raw
  $checks = @(
    "public.profiles", "public.landing_config", "public.membership_content",
    "ROW LEVEL SECURITY", "CREATE POLICY", "CREATE TRIGGER",
    "handle_new_user", "storage.buckets"
  )
  $ok = 0
  foreach ($p in $checks) { if ($sql -match [regex]::Escape($p)) { $ok++ } }
  Pass "SQL: $ok / $($checks.Count)"
}

Section "12. BALANCE EDGE FUNCTIONS"
foreach ($ef in @(
    @{ P = "supabase/functions/stripe-webhook/index.ts"; D = "stripe-webhook" },
    @{ P = "supabase/functions/bunny-token/index.ts"; D = "bunny-token" }
  )) {
  $full = Join-Path $Root $ef.P
  if (Test-Path $full) {
    $c = Get-Content $full -Raw
    $open = ([regex]::Matches($c, '\{')).Count
    $close = ([regex]::Matches($c, '\}')).Count
    if ([math]::Abs($open - $close) -le 2) { Pass "$($ef.D) balance OK ($open / $close)" }
    else { Warn "$($ef.D) desbalance ($open / $close)" }
  }
}

Section "13. GITHUB ACTIONS"
if (Test-Path (Join-Path $Root ".github/workflows/verify.yml")) { Pass "verify.yml existe" }
else { Warn "No existe .github/workflows/verify.yml" }

Section "14. VSCODE CONFIG"
foreach ($vc in @(".vscode/settings.json", ".vscode/extensions.json")) {
  $full = Join-Path $Root $vc
  if (Test-Path $full) {
    $raw = Get-Content $full -Raw
    $cleaned = $raw -replace '(?m)^\s*//.*$', '' -replace ',\s*\}', '}' -replace ',\s*\]', ']'
    try { $null = $cleaned | ConvertFrom-Json; Pass "$vc valido" }
    catch { Warn "$vc tiene formato no estandar (OK para VSCode)" }
  }
  else { Warn "Falta $vc" }
}

Section "15. SEGURIDAD"
$secPatterns = @(
  @{ P = 'sk_live_[a-zA-Z0-9]{20,}'; D = "Stripe LIVE key" },
  @{ P = 'sk_test_[a-zA-Z0-9]{20,}'; D = "Stripe TEST key" },
  @{ P = 'AKIA[0-9A-Z]{16}'; D = "AWS Access Key" },
  @{ P = '-----BEGIN.*PRIVATE KEY'; D = "Clave privada PEM" },
  @{ P = 'service_role_key\s*=\s*"eyJ'; D = "Service role key con valor hardcodeado" }
)
$scanFiles = @(
  "frontend/index.html",
  "supabase/functions/stripe-webhook/index.ts",
  "supabase/functions/bunny-token/index.ts"
)
$secIssues = 0
foreach ($sf in $scanFiles) {
  $full = Join-Path $Root $sf
  if (-not (Test-Path $full)) { continue }
  $c = Get-Content $full -Raw
  foreach ($sp in $secPatterns) {
    if ($c -match $sp.P) { Fail "$($sp.D) en $sf"; $secIssues++ }
  }
}
if ($secIssues -eq 0) { Pass "Sin claves criticas expuestas" }

if (Test-Path (Join-Path $Root ".git")) {
  Push-Location $Root
  $tracked = git ls-files 2>$null | Select-String -Pattern "^\.env$"
  Pop-Location
  if ($tracked) { Fail ".env esta en Git - PELIGRO" }
  else { Pass ".env NO esta en Git" }
}

Section "16. GIT"
if (Test-Path (Join-Path $Root ".git")) {
  Push-Location $Root
  try {
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    $commits = git rev-list --count HEAD 2>$null
    $status = git status --porcelain 2>$null
    Pass "Git OK (rama: $branch, commits: $commits)"
    if ($status) { Warn "$(($status | Measure-Object).Count) archivo(s) sin commitear" }
    else { Pass "Working tree limpio" }
  }
  finally { Pop-Location }
}
else { Warn "No hay repositorio Git" }

Section "17. TAMANOS"
foreach ($f in @(
    "frontend/index.html",
    "database/schema.sql",
    "supabase/functions/stripe-webhook/index.ts",
    "supabase/functions/bunny-token/index.ts"
  )) {
  $full = Join-Path $Root $f
  if (Test-Path $full) { Info "$f : $([math]::Round((Get-Item $full).Length/1KB,2)) KB" }
}

Section "18. ESTADISTICAS"
$allFiles = Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue |
Where-Object { $_.FullName -notmatch "\\node_modules\\|\\\.git\\|\\\.tmp\\" }
Info "Total archivos: $(($allFiles | Measure-Object).Count)"
Info "Tamano total: $([math]::Round((($allFiles | Measure-Object -Property Length -Sum).Sum)/1MB, 2)) MB"

$duration = (Get-Date) - $StartTs

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  RESUMEN" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PASS:  $($global:PassCount)" -ForegroundColor Green
Write-Host "  WARN:  $($global:WarnCount)" -ForegroundColor Yellow
Write-Host "  FAIL:  $($global:FailCount)" -ForegroundColor Red
Write-Host "  Tiempo: $([math]::Round($duration.TotalSeconds,2))s"
Write-Host ""

if ($global:Issues.Count -gt 0) {
  Write-Host "--- PROBLEMAS ---" -ForegroundColor Yellow
  foreach ($i in $global:Issues) {
    $parts = $i -split '\|', 2
    $color = if ($parts[0] -eq "FAIL") { "Red" } else { "Yellow" }
    Write-Host "  [$($parts[0])] $($parts[1])" -ForegroundColor $color
  }
  Write-Host ""
}

if ($global:FailCount -eq 0 -and $global:WarnCount -eq 0) {
  Write-Host "PROYECTO PERFECTO" -ForegroundColor Green
  $exitCode = 0
}
elseif ($global:FailCount -eq 0) {
  Write-Host "PROYECTO LISTO (solo warnings)" -ForegroundColor Yellow
  $exitCode = 0
}
else {
  Write-Host "PROYECTO CON $($global:FailCount) ERRORES CRITICOS" -ForegroundColor Red
  $exitCode = 1
}

if ($Json) {
  $logDir = Join-Path $Root "logs"
  if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
  $jsonPath = Join-Path $logDir "audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
  [pscustomobject]@{
    timestamp = (Get-Date).ToString("o")
    root      = $Root
    duration  = [math]::Round($duration.TotalSeconds, 2)
    passed    = $global:PassCount
    warnings  = $global:WarnCount
    failed    = $global:FailCount
    issues    = $global:Issues
  } | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
  Write-Host "Reporte JSON: $jsonPath" -ForegroundColor Cyan
}

Write-Host ""
exit $exitCode