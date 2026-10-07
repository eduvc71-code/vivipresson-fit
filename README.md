# VIVIPREFIT - Plataforma de Membresias Fitness

**Programa de Entrenamiento y Estilo de Vida Saludable**
Membresia mensual: **USD 40 / mes**

## Estructura del Proyecto

```
D:\ViviProfit\
  frontend/                    SPA HTML5 + Tailwind
  supabase/                    Backend BaaS
    functions/
      stripe-webhook/          Edge Function Stripe
      bunny-token/             Edge Function Bunny
    migrations/
  database/
    schema.sql                 Esquema PostgreSQL + RLS
  scripts/
    devops/                    Scripts de automatizacion
  docs/
  media/
  .env.example                 Plantilla de variables
  package.json
  README.md
```

## Inicio Rapido

### 1. Instalar dependencias
```
npm install
```

### 2. Configurar variables de entorno
```
Copy-Item .env.example .env
notepad .env
```

### 3. Aplicar schema a Supabase
```
psql "host=db.hquwcljvnofhxtvrwjis.supabase.co port=5432 dbname=postgres user=postgres" -f database/schema.sql
```

### 4. Desplegar Edge Functions
```
npm run supabase:functions
```

### 5. Iniciar servidor local
```
npm run dev
```

Abrir http://localhost:3000

## Stack Tecnologico

| Capa      | Tecnologia                       |
|-----------|----------------------------------|
| Frontend  | HTML5, Tailwind CSS, JS vanilla  |
| Backend   | Supabase (PostgreSQL + RLS)      |
| Pagos     | Stripe Billing                   |
| Streaming | Bunny Stream (HLS + SHA256)      |
| Hosting   | Vercel                           |

## Licencia
UNLICENSED - Todos los derechos reservados VIVIPREFIT 2026
