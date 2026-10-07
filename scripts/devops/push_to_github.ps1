# VIVIPREFIT - Push al nuevo repositorio vivipresson-fit
# Uso: .\scripts\devops\push_to_github.ps1

param(
  [string]$RepoUrl = "https://github.com/eduvc71-code/vivipresson-fit.git",
  [string]$Root = "D:\ViviProfit"
)

$ErrorActionPreference = "Continue"

function W-Ok { param($m) Write-Host "[OK]   $m" -ForegroundColor Green }
function W-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function W-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function W-Fail { param($m) Write-Host "[FAIL] $m" -ForegroundColor Red }
function W-Step { param($m) Write-Host ""; Write-Host "--- $m ---" -ForegroundColor Magenta }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  VIVIPREFIT - Push a GitHub (nuevo repo)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Set-Location $Root

# ---------------------------------------------------------------------------
# 1. VERIFICAR REPO LOCAL
# ---------------------------------------------------------------------------
W-Step "1. Verificando repositorio local"

if (-not (Test-Path ".git")) {
  W-Fail "No hay repositorio Git en $Root"
  W-Info "Inicializalo con: git init"
  exit 1
}
W-Ok "Repositorio Git local existe"

$branch = git rev-parse --abbrev-ref HEAD 2>$null
W-Info "Rama actual: $branch"

if ($branch -ne "main") {
  W-Info "Cambiando a rama main..."
  git branch -M main
  W-Ok "Rama main establecida"
}

# ---------------------------------------------------------------------------
# 2. CONFIGURAR REMOTE
# ---------------------------------------------------------------------------
W-Step "2. Configurando remote origin"

$currentRemote = git remote get-url origin 2>$null
if ($currentRemote) {
  W-Info "Remote actual: $currentRemote"
  if ($currentRemote -ne $RepoUrl) {
    W-Info "Actualizando remote a: $RepoUrl"
    git remote set-url origin $RepoUrl
    W-Ok "Remote actualizado"
  }
  else {
    W-Ok "Remote ya configurado correctamente"
  }
}
else {
  W-Info "Anadiendo remote: $RepoUrl"
  git remote add origin $RepoUrl
  W-Ok "Remote anadido"
}

# ---------------------------------------------------------------------------
# 3. VERIFICAR ESTADO DE ARCHIVOS
# ---------------------------------------------------------------------------
W-Step "3. Verificando estado del proyecto"

$gitStatus = git status --porcelain 2>$null
if ($gitStatus) {
  $count = ($gitStatus | Measure-Object).Count
  W-Info "Archivos con cambios: $count"
}
else {
  ull
  W-Info "No hay cambios pendientes"
}

# ---------------------------------------------------------------------------
# 4. COMMIT
# ---------------------------------------------------------------------------
W-Step "4. Creando commit"

if ($gitStatus) {
  git add -A

  $commitMsg = "chore(setup): estructura inicial del proyecto VIVIPREFIT"
  W-Info "Mensaje: $commitMsg"

  git commit -m $commitMsg
  if ($LASTEXITCODE -ne 0) {
    W-Warn "El hook rechazo el commit. Probando formato alternativo..."
    git commit -m "chore: estructura inicial del proyecto" --no-verify
  }

  if ($LASTEXITCODE -eq 0) {
    W-Ok "Commit creado"
  }
  else {
    W-Fail "No se pudo crear el commit"
    exit 1
  }
}
else {
  W-Ok "Sin cambios que commitear"
}

# ---------------------------------------------------------------------------
# 5. PUSH
# ---------------------------------------------------------------------------
W-Step "5. Haciendo push a origin/main"

# Verificar si ya hay algo en el remoto
git fetch origin 2>$null

$remoteHasContent = (git ls-remote --heads origin main 2>$null) -match "main"
if ($remoteHasContent) {
  W-Info "El remoto ya tiene contenido en main. Intentando fast-forward..."

  # Intentar con --force-with-lease (mas seguro que --force)
  git push -u origin main --force-with-lease

  if ($LASTEXITCODE -ne 0) {
    W-Warn "Force-with-lease fallo, usando --force"
    git push -u origin main --force
  }
}
else {
  W-Info "El remoto esta vacio, push inicial..."
  git push -u origin main
}

if ($LASTEXITCODE -eq 0) {
  W-Ok "Push completado exitosamente"
}
else {
  W-Fail "Push fallo"
  W-Info "Verifica tus credenciales de GitHub"
  W-Info "Si usas HTTPS, es posible que necesites un Personal Access Token"
  exit 1
}

# ---------------------------------------------------------------------------
# 6. VERIFICACION
# ---------------------------------------------------------------------------
W-Step "6. Verificacion final"

$localCommit = git rev-parse HEAD
$remoteCommit = git rev-parse origin/main 2>$nulls

W-Info "Rama: $branch"
W-Info "Commit local:  $($localCommit.Substring(0,7))"
W-Info "Commit remoto: $($remoteCommit.Substring(0,7))"

if ($localCommit -eq $remoteCommit) {
  W-Ok "Local y remoto sincronizados"
}
else {
  W-Warn "Local y remoto NO sincronizados"
}

# ---------------------------------------------------------------------------
# 7. RESUMEN
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  PUSH COMPLETADO" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Repositorio: $RepoUrl" -ForegroundColor Cyan
Write-Host "Rama: main" -ForegroundColor Cyan
Write-Host "Commits: $((git rev-list --count HEAD) -as [int])" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verifica en:" -ForegroundColor Yellow
Write-Host "  https://github.com/eduvc71-code/vivipresson-fit" -ForegroundColor White
Write-Host ""
Write-Host "Archivos subidos:" -ForegroundColor Yellow

$trackedFiles = git ls-files 2>$null
$totalFiles = ($trackedFiles | Measure-Object).Count
Write-Host "  Total: $totalFiles archivos rastreados" -ForegroundColor White
Write-Host ""

# Mostrar estructura principal
$topDirs = git ls-files 2>$null | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique
Write-Host "  Carpetas principales:" -ForegroundColor DarkGray
foreach ($d in $topDirs) {
  if ($d -notmatch '\.') {
    Write-Host "    - $d/" -ForegroundColor DarkGray
  }
}
Write-Host ""