# DOCUMENTO DE ARQUITECTURA Y ESPECIFICACIÓN DE INGENIERÍA
## Proyecto: Plataforma de Membresías Fitness — VIVIPREFIT
**Concepto Comercial:** Programa de Entrenamiento y Estilo de Vida Saludable (Renovación Mensual)  
**Dominio Objetivo:** vivipressonfit.com  
**Modelo de Cobro:** Suscripción mensual unificada de **$us. 40.- / mes**  
**Estado:** Producción / Listo para Implementación  

---

## 1. RESUMEN EJECUTIVO Y ALCANCE FUNCIONAL

Este documento define la arquitectura técnica y funcional para la plataforma de membresías fitness VIVIPREFIT. El sistema opera sobre una arquitectura desacoplada (Jamstack) de alto rendimiento, costos operativos mínimos, seguridad de contenido audiovisual y automatización total del ciclo de cobros.

La propuesta comercial se unifica en una **membresía integral mensual de $us. 40.-**, eliminando la fragmentación en tiers complejos y enfocándose en 4 pilares centrales:

### 1.1. Pilares del Programa:
1. **Biblioteca de Clases Grabadas (Streaming Seguro):**
   * **GAP:** Glúteos, Abdomen y Piernas para máxima firmeza y tonificación.
   * **Full Body:** Entrenamiento integral de todos los grupos musculares.
   * **Cardio HIIT:** Rutinas de alta intensidad para quema calórica y resistencia cardiovascular.
   * **Fuerza + Aeróbico:** Combinación balanceada de potencia muscular y capacidad aeróbica.
2. **Plan de Entrenamiento Mensual:**
   * **Rutinas de Fuerza (3 veces por semana):** Estructuras adaptables para realizar en casa o en gimnasio.
3. **Nutrición y Acompañamiento:**
   * **Educación Alimentaria:** Guías y materiales sobre alimentación consciente, saludable y sostenible.
   * **Soporte Personalizado vía WhatsApp:** Canal directo y verificado para resolución continua de consultas y acompañamiento motivacional.
4. **Dinámica del Servicio:**
   * **Renovación Mensual Continua:** Renovación de rutinas, clases y recursos cada ciclo para asegurar progresión y retención.

---

## 2. ARQUITECTURA DE SOFTWARE (JAMSTACK DESACOPLADO)

```
+--------------------------------------------------------------------------+
|                        CAPA DE PRESENTACIÓN (Frontend)                   |
|                   HTML5 / Tailwind CSS / Vercel Edge / PWA               |
|   - Landing Page con Copy del Programa ($us 40/mes)                      |
|   - Dashboard de Alumna (Biblioteca GAP/Full Body/HIIT/Fuerza)           |
|   - Widget de Acceso Directo a WhatsApp verificado                       |
+--------------------------------------------------------------------------+
       │ Consultas API y Auth             │ Redirección Checkout ($40/mes)
       ▼                                  ▼
+------------------------------------+    +--------------------------------+
|       CAPA DE DATOS (BaaS)         |    |   CAPA TRANSACCIONAL (Pagos)   |
|   Supabase / PostgreSQL con RLS    |    |   Stripe Billing / Checkout    |
|   - Profiles (Suscripción activa)  |    |   - Precio: $40.00 USD / mes   |
|   - Contenidos y Rutinas           |    +--------------------------------+
+------------------------------------+                     │
       │                                                   │ Webhooks
       │ Genera Token Expirable (HLS)                      ▼
       │                              Actualiza estado: 'active' / 'inactive'
       ▼
+--------------------------------------------------------------------------+
|                     CAPA MULTIMEDIA & RECURSOS                           |
|   - Bunny Stream: Streaming de video con DRM y bloqueo de dominio        |
|   - Supabase Storage: Bucket privado para PDFs de Educación Alimentaria  |
+--------------------------------------------------------------------------+
```

---

## 3. MODELO DE DATOS (POSTGRESQL / SUPABASE)

### 3.1. Tabla: `landing_config` (Parametrización Pública)
Almacena variables dinámicas visibles en la Landing Page que pueden ser editadas desde el panel administrativo.

| Campo | Tipo | Restricción | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | TEXT | PRIMARY KEY | Identificador único (Fijo: `'main'`) |
| `coach_name` | TEXT | NOT NULL | Nombre de la coach (`'Vivi'`) |
| `program_title` | TEXT | NOT NULL | 'Programa de Entrenamiento y Estilo de Vida Saludable' |
| `precio_mensual` | NUMERIC | NOT NULL | Valor actual: `40.00` |
| `currency` | TEXT | DEFAULT 'USD' | Código de divisa (`USD`) |
| `whatsapp_support_number`| TEXT | NOT NULL | Línea oficial de WhatsApp para soporte |
| `updated_at` | TIMESTAMPTZ | DEFAULT NOW() | Auditoría de última modificación |

### 3.2. Tabla: `profiles` (Usuarios y Suscripciones)
Maneja la información de membresía y sincronización con pasarela.

| Campo | Tipo | Restricción | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | UUID | REFERENCES auth.users | Identificador de usuario en Supabase Auth |
| `email` | TEXT | UNIQUE, NOT NULL | Correo de la alumna |
| `full_name` | TEXT | Opcional | Nombre de la alumna |
| `phone_number` | TEXT | Opcional | Teléfono para verificación en canal WhatsApp |
| `stripe_customer_id` | TEXT | Opcional | ID de cliente en Stripe |
| `stripe_sub_id` | TEXT | Opcional | ID de la suscripción recurrente en Stripe |
| `plan_status` | TEXT | DEFAULT 'inactive' | Estados: `'active'`, `'canceled'`, `'past_due'`, `'inactive'` |
| `current_period_end` | TIMESTAMPTZ | Opcional | Fecha de vencimiento del período abonado |
| `updated_at` | TIMESTAMPTZ | DEFAULT NOW() | Fecha de última sincronización |

### 3.3. Tabla: `membership_content` (Contenido Mensual Dinámico)
Organiza los recursos renovables mes a mes.

| Campo | Tipo | Restricción | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Identificador único del recurso |
| `cycle_date` | DATE | NOT NULL | Mes/Año correspondiente al ciclo (ej. `2026-10-01`) |
| `category` | TEXT | NOT NULL | `'GAP'`, `'Full Body'`, `'Cardio HIIT'`, `'Fuerza + Aerobico'`, `'Rutina Fuerza'`, `'Nutricion'` |
| `title` | TEXT | NOT NULL | Título de la clase o material |
| `bunny_video_id` | TEXT | Opcional | ID del video en Bunny Stream para streaming cifrado |
| `storage_path` | TEXT | Opcional | Ruta relativa en Supabase Storage (para guías nutricionales) |
| `target_mode` | TEXT | DEFAULT 'Ambos' | `'Casa'`, `'Gimnasio'`, `'Ambos'` |
| `is_published` | BOOLEAN | DEFAULT false | Control de visibilidad pública para alumnas |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() | Fecha de alta del recurso |

---

## 4. POLÍTICAS DE SEGURIDAD (ROW LEVEL SECURITY - RLS)

### 4.1. `landing_config`
* **SELECT:** Abierto al rol público (`anon`, `authenticated`).
* **UPDATE:** Restringido a la cuenta de administración certificada (`auth.jwt() ->> 'email' = 'admin@vivipressonfit.com'`).

### 4.2. `profiles`
* **SELECT/UPDATE:** Restringido estrictamente a la fila propia mediante `auth.uid() = id`.
* **SERVICE_ROLE:** Las funciones de Webhook actualizan el registro saltándose RLS con clave segura de backend.

### 4.3. `membership_content`
* **SELECT:** Permitido solo si el usuario autenticado tiene estado de suscripción vigente:
  ```sql
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
      AND profiles.plan_status = 'active'
  )
  ```
* **INSERT / UPDATE / DELETE:** Exclusivo para el rol administrador.

---

## 5. FLUJOS LÓGICOS DE OPERACIÓN

### 5.1. Proceso de Alta y Facturación ($us. 40.-/mes)
1. **Checkout:** La usuaria pulsa *"Comenzar ahora"* e ingresa al flujo de Stripe Checkout con cobro recurrente mensual de $40 USD.
2. **Webhook Receiver:** Stripe emite `checkout.session.completed` y `invoice.paid`. El backend valida la firma criptográfica y actualiza `profiles.plan_status = 'active'`.
3. **Acceso Inmediato:** La usuaria es redirigida a su dashboard con todas las categorías desbloqueadas.

### 5.2. Visualización Segura de Video
1. La alumna selecciona una clase (GAP, Full Body, Cardio HIIT o Fuerza + Aeróbico).
2. El frontend solicita un token de sesión a una Supabase Edge Function.
3. La función verifica que `plan_status == 'active'` y emite un token de Bunny Stream firmado con expiración corta (120 minutos).
4. El video se reproduce por HLS bloqueando descargas directas y restringiendo el origen a `vivipressonfit.com`.

### 5.3. Acompañamiento por WhatsApp
* Dentro del dashboard autenticado se incluye un enlace directo parametrizado:
  `https://wa.me/{whatsapp_support_number}?text=Hola%20Vivi,%20soy%20{full_name}%20y%20tengo%20una%20consulta`
* Esto asegura un canal ágil y personal de atención para las alumnas.

---

## 6. CRONOGRAMA DE EJECUCIÓN (5 FASES)

* **Fase 1: Infraestructura y Entornos (Día 1):** Configuración de dominio, DNS, repositorio Git y cuenta de Stripe en modo Sandbox.
* **Fase 2: Esquema de Datos y RLS (Días 2-3):** Creación de tablas (`landing_config`, `profiles`, `membership_content`) y políticas de seguridad en Supabase.
* **Fase 3: Pasarela y Video CDN (Día 4):** Configuración de producto recurrente de $40/mes en Stripe y zona de almacenamiento Bunny Stream.
* **Fase 4: Frontend y Dashboard (Días 5-6):** Implementación de la Landing Page con el copy persuasivo, catálogo mensual y botón de soporte WhatsApp.
* **Fase 5: Pruebas y Despliegue (Día 7):** Auditoría de webhooks, verificación de streaming protegido y despliegue final en Vercel.