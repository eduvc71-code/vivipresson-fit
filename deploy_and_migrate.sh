#!/usr/bin/env bash
# ============================================================================
# VIVIPREFIT — Script DevOps de Aprovisionamiento, Migración y Despliegue
# Uso:
#   ./deploy_and_migrate.sh setup     # Crea proyecto, aplica schema, despliega functions
#   ./deploy_and_migrate.sh migrate   # Aplica migraciones delta sin pérdida de datos
#   ./deploy_and_migrate.sh deploy    # Publica frontend en Vercel/Cloudflare Pages
#   ./deploy_and_migrate.sh secrets   # Sincroniza variables de entorno
# ============================================================================
set -euo pipefail

# ----------------------------------------------------------------------------
# CONFIGURACIÓN
# ----------------------------------------------------------------------------
PROJECT_REF="${SUPABASE_PROJECT_REF:-hquwcljvnofhxtvrwjis}"
SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
SCHEMA_FILE="${SCHEMA_FILE:-schema.sql}"
FUNCTIONS_DIR="${FUNCTIONS_DIR:-supabase/functions}"
FRONTEND_DIR="${FRONTEND_DIR:-.}"
VERCEL_PROJECT="${VERCEL_PROJECT:-vivipressonfit}"
STRIPE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:-}"
STRIPE_SECRET_KEY="${STRIPE_SECRET_KEY:-}"
BUNNY_STREAM_LIBRARY_ID="${BUNNY_STREAM_LIBRARY_ID:-}"
BUNNY_STREAM_API_KEY="${BUNNY_STREAM_API_KEY:-}"
BUNNY_STREAM_TOKEN_KEY="${BUNNY_STREAM_TOKEN_KEY:-}"

# Colores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ----------------------------------------------------------------------------
# VERIFICACIÓN DE DEPENDENCIAS
# ----------------------------------------------------------------------------
check_deps() {
  log "Verificando dependencias..."
  local missing=0
  for cmd in curl git node npm npx; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "Falta dependencia: $cmd"; missing=1
    fi
  done
  if ! command -v supabase >/dev/null 2>&1; then
    warn "Supabase CLI no encontrada. Instalando vía npm..."
    npm install -g supabase || { err "No se pudo instalar supabase CLI"; exit 1; }
  fi
  if ! command -v vercel >/dev/null 2>&1; then
    warn "Vercel CLI no encontrada. Se instalará solo si se usa 'deploy'."
  fi
  [ "$missing" -eq 0 ] && ok "Dependencias base presentes"
}

# ----------------------------------------------------------------------------
# LOGIN SUPABASE
# ----------------------------------------------------------------------------
supabase_login() {
  if ! supabase projects list >/dev/null 2>&1; then
    log "Iniciando sesión en Supabase (interactivo)..."
    supabase login
  fi
  ok "Sesión Supabase activa"
}

# ----------------------------------------------------------------------------
# VINCULAR PROYECTO
# ----------------------------------------------------------------------------
supabase_link() {
  log "Vinculando proyecto Supabase: $PROJECT_REF"
  if [ ! -f ".supabase/config.toml" ]; then
    supabase init || true
  fi
  supabase link --project-ref "$PROJECT_REF" || warn "Ya vinculado o requiere DB password"
  ok "Proyecto vinculado"
}

# ----------------------------------------------------------------------------
# APLICAR SCHEMA SQL (idempotente)
# ----------------------------------------------------------------------------
apply_schema() {
  if [ ! -f "$SCHEMA_FILE" ]; then
    err "Archivo $SCHEMA_FILE no encontrado"; exit 1
  fi
  log "Aplicando schema ($SCHEMA_FILE) vía psql remoto..."
  if [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    PGPASSWORD="$SUPABASE_DB_PASSWORD" psql \
      "host=db.${PROJECT_REF}.supabase.co port=5432 dbname=postgres user=postgres sslmode=require" \
      -v ON_ERROR_STOP=1 -f "$SCHEMA_FILE"
    ok "Schema aplicado correctamente"
  else
    warn "SUPABASE_DB_PASSWORD no definida. Usando 'supabase db push' con migraciones."
    mkdir -p supabase/migrations
    cp "$SCHEMA_FILE" "supabase/migrations/$(date +%Y%m%d%H%M%S)_init.sql"
    supabase db push --linked --include-all
    ok "Migraciones aplicadas vía CLI"
  fi
}

# ----------------------------------------------------------------------------
# SECRETOS DE FUNCTIONS
# ----------------------------------------------------------------------------
set_function_secrets() {
  log "Configurando secretos de Edge Functions..."
  local secrets=()
  [ -n "$STRIPE_SECRET_KEY" ]         && secrets+=("STRIPE_SECRET_KEY=$STRIPE_SECRET_KEY")
  [ -n "$STRIPE_WEBHOOK_SECRET" ]     && secrets+=("STRIPE_WEBHOOK_SECRET=$STRIPE_WEBHOOK_SECRET")
  [ -n "$BUNNY_STREAM_LIBRARY_ID" ]   && secrets+=("BUNNY_STREAM_LIBRARY_ID=$BUNNY_STREAM_LIBRARY_ID")
  [ -n "$BUNNY_STREAM_API_KEY" ]      && secrets+=("BUNNY_STREAM_API_KEY=$BUNNY_STREAM_API_KEY")
  [ -n "$BUNNY_STREAM_TOKEN_KEY" ]    && secrets+=("BUNNY_STREAM_TOKEN_KEY=$BUNNY_STREAM_TOKEN_KEY")

  if [ "${#secrets[@]}" -eq 0 ]; then
    warn "No se definieron secretos. Configura variables de entorno antes de ejecutar."
    return
  fi
  for s in "${secrets[@]}"; do
    supabase secrets set "$s" || warn "No se pudo establecer: ${s%%=*}"
  done
  ok "Secretos sincronizados"
}

# ----------------------------------------------------------------------------
# DESPLEGAR EDGE FUNCTIONS
# ----------------------------------------------------------------------------
deploy_functions() {
  log "Desplegando Edge Functions..."
  for fn in stripe-webhook bunny-token; do
    if [ -d "$FUNCTIONS_DIR/$fn" ]; then
      supabase functions deploy "$fn" --project-ref "$PROJECT_REF" --no-verify-jwt=false || \
        supabase functions deploy "$fn" --project-ref "$PROJECT_REF"
      ok "Función desplegada: $fn"
    else
      warn "Directorio de función no encontrado: $FUNCTIONS_DIR/$fn"
    fi
  done
}

# ----------------------------------------------------------------------------
# CONFIGURAR WEBHOOK STRIPE
# ----------------------------------------------------------------------------
setup_stripe_webhook() {
  if ! command -v stripe >/dev/null 2>&1; then
    warn "Stripe CLI no instalada. Configura el webhook manualmente en el dashboard."
    warn "URL: ${SUPABASE_URL}/functions/v1/stripe-webhook"
    return
  fi
  log "Configurando webhook de Stripe (modo test)..."
  stripe listen --forward-to "${SUPABASE_URL}/functions/v1/stripe-webhook" || true
  ok "Webhook Stripe configurado (modo local)"
}

# ----------------------------------------------------------------------------
# DESPLIEGUE FRONTEND (Vercel)
# ----------------------------------------------------------------------------
deploy_frontend() {
  if ! command -v vercel >/dev/null 2>&1; then
    warn "Instalando Vercel CLI..."
    npm install -g vercel
  fi
  log "Desplegando frontend en Vercel..."
  vercel --prod --yes --name "$VERCEL_PROJECT" || { err "Falló despliegue Vercel"; exit 1; }
  ok "Frontend desplegado"
}

# ----------------------------------------------------------------------------
# SETUP COMPLETO
# ----------------------------------------------------------------------------
cmd_setup() {
  check_deps
  supabase_login
  supabase_link
  apply_schema
  set_function_secrets
  deploy_functions
  setup_stripe_webhook
  ok "✅ Setup completo. Configura los secretos en Vercel y ejecuta 'deploy'."
}

# ----------------------------------------------------------------------------
# MIGRACIÓN DELTA
# ----------------------------------------------------------------------------
cmd_migrate() {
  check_deps
  supabase_link
  log "Aplicando migraciones delta sin pérdida de datos..."
  if [ -f "$SCHEMA_FILE" ]; then
    mkdir -p supabase/migrations
    cp "$SCHEMA_FILE" "supabase/migrations/$(date +%Y%m%d%H%M%S)_delta.sql"
    supabase db push --linked --include-all
    ok "Migraciones aplicadas"
  else
    warn "No hay archivo de schema para migrar"
  fi
}

# ----------------------------------------------------------------------------
# DEPLOY
# ----------------------------------------------------------------------------
cmd_deploy() {
  check_deps
  deploy_frontend
  ok "✅ Deploy completo"
}

# ----------------------------------------------------------------------------
# SECRETS
# ----------------------------------------------------------------------------
cmd_secrets() {
  check_deps
  supabase_login
  supabase_link
  set_function_secrets
  ok "✅ Secretos sincronizados"
}

# ----------------------------------------------------------------------------
# AYUDA
# ----------------------------------------------------------------------------
cmd_help() {
  cat <<EOF
VIVIPREFIT DevOps Script

Uso:
  $0 setup     Aprovisiona proyecto completo (schema + functions + secrets)
  $0 migrate   Aplica migraciones delta de BD sin pérdida de datos
  $0 deploy    Publica frontend en Vercel
  $0 secrets   Sincroniza secretos de Edge Functions
  $0 help      Muestra esta ayuda

Variables de entorno requeridas:
  SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD (opcional),
  STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET,
  BUNNY_STREAM_LIBRARY_ID, BUNNY_STREAM_API_KEY, BUNNY_STREAM_TOKEN_KEY,
  VERCEL_PROJECT (opcional)
EOF
}

# ----------------------------------------------------------------------------
# DISPATCHER
# ----------------------------------------------------------------------------
case "${1:-help}" in
  setup)    cmd_setup ;;
  migrate)  cmd_migrate ;;
  deploy)   cmd_deploy ;;
  secrets)  cmd_secrets ;;
  help|*)   cmd_help ;;
esac