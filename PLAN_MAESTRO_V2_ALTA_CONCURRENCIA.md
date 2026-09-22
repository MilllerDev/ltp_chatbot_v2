# Plan Maestro v2.1 — Plataforma de Mensajería Omnicanal de Alta Concurrencia (WhatsApp + Web)

> **Alcance de este documento.** Diseño técnico de la plataforma con **dos
> canales de cliente**: WhatsApp (dependiente de Meta) y Web (bajo nuestro
> control total). Cubre el motor de campañas promocionales (Fase 1, sin IA) y
> la ruta de evolución hacia la capa conversacional con IA (Fase 2). Sustituye
> y corrige `Plan_Maestro_Arquitectura.md` (rama `harol`).
>
> **Fecha:** 2026-09-18 · **Estado:** propuesta para revisión

## Cambios respecto a v2

La v2 era íntegramente WhatsApp-céntrica. Su tesis principal —"el cuello de
botella es Meta, no tu stack"— es **cierta para WhatsApp y falsa para Web**.
En el canal web no hay tercero: el techo de concurrencia lo pone nuestra
arquitectura, y ahí sí se cobra cada decisión de stack. Esta revisión:

- Introduce la **abstracción de canal** (§4.3) para que campañas, sesiones y
  la futura IA no sepan si hablan con Meta o con un socket.
- Añade el diseño completo del **canal web de alta concurrencia** (§7):
  sockets, sesiones, reconexión con resume, rate limiting por cliente,
  campañas a conectados y desconectados, protección contra abuso.
- **Adelanta la sesión conversacional como proceso** de Fase 2 a Fase 1: el
  canal web la necesita desde el primer día, con o sin IA.
- Añade SLOs, métricas, infraestructura, riesgos y costos específicos de Web.
- Corrige la tesis 1 para acotarla a WhatsApp y añade la tesis 4.

---

## 0. Tesis del documento

Cuatro afirmaciones que sostienen todo el diseño:

1. **En WhatsApp el cuello de botella no es tu servidor: es Meta.** El límite
   duro son **80 mensajes por segundo por número de teléfono** (hasta 1.000 MPS
   en tier Unlimited, 20 MPS fijos en números *coexistence*). Ningún lenguaje
   mueve ese techo. La ingeniería consiste en **saturarlo con precisión
   quirúrgica sin excederlo jamás**.

2. **En WhatsApp el caudal de entrada es mayor que el de salida.** Cada
   mensaje enviado genera hasta 3 webhooks de estado. Enviando a 800 MPS
   recibes ~2.400 eventos/s que hay que acusar en milisegundos o Meta reintenta.
   **El ingestor de webhooks es el componente más exigente del canal WhatsApp.**

3. **El canal de marketing de WhatsApp está migrando** a la Marketing Messages
   Lite API. El emisor va detrás de una abstracción con dos adaptadores desde
   el día uno.

4. **En Web el techo lo ponemos nosotros.** No hay tarifa por mensaje, no hay
   plantillas, no hay ventana de 24 h, no hay 80 MPS. Lo que hay es un problema
   clásico de sistemas: **decenas o cientos de miles de conexiones persistentes
   abiertas a la vez, fan-out de broadcasts a todas ellas, y clientes hostiles
   o lentos que no pueden degradar a los demás**. Este es exactamente el
   problema para el que el BEAM fue diseñado, y la razón por la que el stack
   elegido en §5 no es una preferencia sino una consecuencia.

Corolario: **elegimos el stack por su modelo de ejecución** (aislamiento por
proceso, backpressure, latencia de cola predecible con muchas conexiones), no
por throughput bruto.

---

## 1. Dónde está realmente el límite: la aritmética

### 1.1 WhatsApp — techo de emisión

| Escenario | MPS efectivo | 100.000 destinatarios |
|---|---:|---:|
| 1 número, tier estándar | 80 | **20 min 50 s** |
| 1 número, *coexistence* | 20 | 83 min 20 s |
| 1 número, tier Unlimited (upgrade) | hasta 1.000 | 1 min 40 s |
| 5 números en paralelo, estándar | 400 | 4 min 10 s |
| 10 números en paralelo, estándar | 800 | 2 min 5 s |

La palanca de escala en WhatsApp es **sharding horizontal sobre múltiples
números**. El número es la unidad de paralelismo de primera clase.

### 1.2 WhatsApp — techo de audiencia (independiente del anterior)

Los *messaging limits* limitan **cuántos usuarios únicos** puedes iniciar
conversación en 24 h móviles:

```
250 (nuevo)  →  2.000  →  10.000  →  100.000  →  Ilimitado
```

- De 250 a 2.000: verificación de negocio, o 2.000 mensajes entregados a
  números únicos fuera de la ventana de servicio en 30 días con plantillas de
  alta calidad.
- De 2.000 en adelante: escalado automático si mantienes calidad alta **y usas
  al menos la mitad del límite actual cada 7 días**. Meta reevalúa cada ~6 h.
- **Riesgo asimétrico:** subir de tier toma días; **bajar toma 24 h** si la
  calidad cae a Amarillo o Rojo.

> Implicación: el sistema necesita una política de *warm-up* que consuma
> deliberadamente ≥50% del límite cada 7 días, y un *circuit breaker* ligado
> al quality rating. Lógica de negocio que ninguna herramienta low-code da.

### 1.3 WhatsApp — presupuesto de latencia por mensaje

| Etapa | Objetivo |
|---|---:|
| Claim del lote en Postgres (`SKIP LOCKED`) | < 2 ms / 500 filas |
| Render de plantilla + payload JSON | < 0,1 ms |
| Espera del pacer (token bucket) | determinista por diseño |
| `POST` a Graph API (p50 / p99) | 90 ms / 400 ms |
| Persistencia de `wa_message_id` (batch) | amortizado < 0,5 ms |

El tiempo lo domina la red hacia Meta; se absorbe con **concurrencia de
conexiones**: a p99 = 400 ms y 80 MPS, ~32 peticiones en vuelo por número.

### 1.4 Web — donde el stack sí es el techo

Aquí la unidad no es "mensajes por segundo" sino **conexiones abiertas
simultáneas** y **fan-out**. Tres números gobiernan el diseño:

**a) Memoria por conexión.** Phoenix sostuvo **2 millones de WebSockets en un
solo servidor de 40 núcleos / 128 GB** (limitado por `ulimit`, no por el
runtime), con un piso de pocos KB por socket crudo. Se reporta que máquinas
*commodity* de 4 núcleos / 16 GB sostienen **300K+ sesiones vivas a <50% de
recursos**. Para presupuestar con margen usamos un número conservador que
incluye el proceso de sesión, el canal, buffers y el ring de resume:

```
Presupuesto por sesión web ≈ 30 KB  (socket + channel + sesión + ring buffer)

 10.000 sesiones  →   0,3 GB
100.000 sesiones  →   3,0 GB
500.000 sesiones  →  15,0 GB
```

Un nodo de 4 vCPU / 16 GB soporta cómodamente **100.000 sesiones concurrentes
con headroom del 60%**. La escala se hace **añadiendo nodos**, y gracias al
modelo de PubSub del BEAM (§7.6) añadir un nodo cuesta *un* mensaje extra por
broadcast, no *N*.

**b) Costo de fan-out.** Un broadcast a S sockets conectados en N nodos cuesta:
1 mensaje inter-nodo por nodo + S envíos locales + S escrituras de socket. El
BEAM despacha millones de mensajes de proceso por segundo; el límite práctico
son las **syscalls de escritura en socket**, en el orden de 100–300k/s por
nodo. Fan-out a 100k sockets en un nodo: **< 1 s**.

**c) Clientes lentos.** Un navegador que deja de leer no puede hacer crecer sin
límite la memoria del servidor. La cola de salida por sesión está **acotada**
(§7.3); un cliente que no drena recibe un `resync`, no tumba el nodo.

**Presupuesto de latencia web (sin IA):**

| Etapa | Objetivo |
|---|---:|
| Handshake WebSocket + `join` autorizado | p99 < 200 ms |
| Mensaje cliente → sesión → respuesta guiada | p99 < 100 ms |
| Reconexión con resume (últimos N mensajes) | p99 < 300 ms |
| Broadcast a 100k conectados (último socket) | < 2 s |
| Web Push a desconectados (encolado) | asíncrono, no en el camino crítico |

---

## 2. Restricciones de la plataforma Meta (investigadas)

*(Aplican solo al canal WhatsApp. El canal web no tiene ninguna de ellas.)*

### 2.1 Errores que definen el diseño

| Código | Significado | Respuesta del sistema |
|---|---|---|
| **130429** | Throughput por segundo excedido | **Fallo del pacer.** Alarma crítica. Backoff 1 s → 60 s con jitter, y reducción automática del MPS objetivo en 20%. |
| **131056** | *Pair rate limit* al mismo destinatario | Dedupe por par (emisor, destinatario) con ventana. No reintentar a ciegas. |
| **131047** | Fuera de la ventana de 24 h | Requiere plantilla. Reclasificar, no reintentar igual. |
| **131049 / 131050** | Límite de marketing del usuario / opt-out | **No reintentar nunca.** `suppressed` permanente. |
| **80007 / 613** | Rate limit de Graph API (nivel de app) | Backoff global de la app. |

Todo error almacena el `fbtrace_id`: es el único identificador que Meta acepta
para escalar un caso.

### 2.2 Modelo de precios vigente (desde 2025-07-01)

Cobro **por mensaje entregado**. Categorías: **Marketing** (la más cara;
cualquier plantilla con descuento o lenguaje de reenganche), **Utility**
(operativas; gratis dentro de la ventana de servicio), **Authentication**
(OTP), **Service** (respuestas dentro de la ventana de 24 h).

Dos cambios con fecha:

1. **Perú pasó a facturación en PEN el 2026-04-01 con aumento de tarifas de
   marketing.** Las cifras del plan anterior (`~$0.008–0.012`) son anteriores
   y no sirven para presupuestar.
2. **Desde el 2026-10-01** se vuelven facturables **las respuestas de servicio
   enviadas por un agente humano o por un agente de IA de terceros dentro de la
   ventana de 24 h**. El modelo "el bot responde gratis dentro de la ventana"
   desaparece. **Esto convierte al canal web en la palanca de costo más
   importante de la Fase 2** (§8.4).

Existen además **tiers de volumen** (tarifas menores por umbrales mensuales por
portfolio, con webhooks de tiering) y, desde 2026, ***max-price bidding***.

### 2.3 MM Lite API

Interfaz nueva de Meta para campañas de marketing unidireccionales a gran
escala: mejoras de entrega reportadas del 5% al 30%, filtrado previo de
contactos inactivos (no se pagan) y optimización de contenido. Probable ruta
exclusiva de marketing con retiro gradual del soporte en Cloud API.

> **Decisión:** adaptadores `CloudApi` y `MmLite` detrás del mismo *behaviour*
> de canal, seleccionables **por campaña** para hacer A/B y migrar sin tocar el
> motor.

### 2.4 Restricción geográfica

Desde 2025-04-01 Meta mantiene pausada la entrega de plantillas de Marketing a
usuarios con número de EE.UU. El segmentador excluye `+1` de marketing.

---

## 3. Objetivos de servicio (SLOs)

Sin números, "alta concurrencia" es un adjetivo, no un requisito.

### 3.1 Canal WhatsApp

| SLO | Objetivo | Por qué |
|---|---|---|
| Precisión de pacing | ±2% del MPS objetivo | Debajo desperdicias tiempo; encima, 130429. |
| Errores 130429 | **0** por millón de envíos | Un 130429 es un bug. |
| Ack de webhook entrante | p99 < 50 ms, p999 < 200 ms | Meta reintenta si tardas. |
| Duplicados entregados | < 1 por 10⁶ | Doble promo = reporte de spam. |
| Lag de reconciliación de estado | p99 < 5 s | Dashboard creíble en vivo. |
| Campaña 100k / 1 número | ≤ 22 min | 20 min 50 s teóricos + 5%. |
| Pérdida de eventos de estado | 0 | Se factura por entrega. |
| Recuperación tras caída de nodo | < 30 s, sin reenvíos | Lease + advisory lock. |

### 3.2 Canal Web

| SLO | Objetivo | Por qué |
|---|---|---|
| Sesiones concurrentes por nodo | **≥ 100.000** sostenidas, medidas en carga | Define cuántos nodos compras. |
| Handshake + `join` | p99 < 200 ms | Primer contacto del usuario con el widget. |
| Respuesta guiada (sin IA) | p99 < 100 ms | Percepción de "instantáneo". |
| Fan-out de broadcast a 100k | < 2 s al último socket | Campañas en vivo simultáneas. |
| Reconexión con resume | 100% sin pérdida ni duplicado | Móviles cambian de red constantemente. |
| Aislamiento de cliente abusivo | 0 impacto en p99 de los demás | Un bot no degrada a 99.999 usuarios. |
| Reconexión masiva tras caída de nodo | Absorbida en < 60 s sin cascada | *Thundering herd* controlado con jitter. |
| Entrega de Web Push | ≥ 95% a suscripciones válidas en < 5 min | Analogo web de la plantilla WhatsApp. |

---

## 4. Arquitectura

### 4.1 Vista general

```
   Meta Webhooks ──▶ INGESTOR WA (Phoenix)          Navegadores ──▶ SOCKETS WEB (Phoenix Channels)
   (status,inbound)  · firma X-Hub-Signature-256                    · token firmado + check_origin
                     · ack 200 < 50 ms                              · 100k+ conexiones / nodo
                     · ETS → COPY por lotes                         · rate limit GCRA por sesión
                            │                                              │
                            │                                   ┌──────────▼──────────┐
                            │                                   │ SESIONES (GenServer  │
                            │                                   │ por conversación,    │
                            │                                   │ DynamicSupervisor,   │
                            │                                   │ ring de resume)      │
                            │                                   └──────────┬──────────┘
                            ▼                                              ▼
              ┌──────────────────────────────────────────────────────────────────────┐
              │  ABSTRACCIÓN DE CANAL  (Ltp.Channel behaviour)                       │
              │  · WhatsApp.CloudApi   · WhatsApp.MmLite   · Web.Socket   · Web.Push │
              └───────────────┬─────────────────────────────────────────┬────────────┘
                              │                                         │
          ┌───────────────────▼───────────────┐         ┌───────────────▼────────────────┐
          │ EMISOR WA — Broadway por número   │         │ FAN-OUT WEB — Phoenix.PubSub   │
          │ Pacer GCRA · Finch · circuit brkr │         │ (:pg) topics por segmento,     │
          └───────────────────┬───────────────┘         │ Web Push (VAPID) a offline     │
                              │                         └───────────────┬────────────────┘
                              ▼                                         ▼
              ┌──────────────────────────────────────────────────────────────────────┐
              │  PostgreSQL 17 — campañas, destinatarios (particionado), sesiones,   │
              │  mensajes, status_events (append-only), push_subscriptions, pgvector │
              └──────────────────────────────────────────────────────────────────────┘
                              ▲
              ┌───────────────┴──────────────────────────────────┐
              │  PLANO DE CONTROL — Phoenix LiveView             │
              │  consola de campañas · warm-up de tiers ·        │
              │  supresiones · alertas de calidad · sesiones     │
              └──────────────────────────────────────────────────┘
```

### 4.2 Principio rector WhatsApp: pinning de número a nodo

El límite de Meta es por número. Cada número se ancla a **exactamente un
nodo** mediante `pg_try_advisory_lock(hash(phone_number_id))`. Un solo nodo
satura sin esfuerzo los 80 MPS; el rate limiting vuelve a ser **local y en
memoria** (`:atomics`, nanosegundos, cero coordinación). Si el nodo cae, el
lock se libera al cerrarse la conexión y otro nodo lo toma en < 30 s.

### 4.3 Abstracción de canal

Campañas, sesiones y la futura IA **no deben saber** por qué canal hablan. Un
*behaviour* con capacidades declaradas evita `case` dispersos por el código:

```elixir
defmodule Ltp.Channel do
  @moduledoc "Contrato de todo canal de entrega. Un módulo por transporte."

  @type capability ::
          :streaming        # se puede entregar token a token (Web sí, WA no)
          | :templates       # requiere plantilla aprobada fuera de ventana (WA)
          | :service_window  # existe ventana de 24 h (WA)
          | :billable        # Meta cobra por mensaje (WA)
          | :presence        # sabemos si el usuario está conectado ahora (Web)
          | :rich_ui         # botones, carruseles, formularios (ambos, distinto)

  @callback capabilities() :: [capability()]
  @callback deliver(Ltp.Message.t(), opts :: keyword()) ::
              {:ok, external_id :: String.t()} | {:error, Ltp.Channel.Error.t()}
  @callback classify_error(term()) :: :permanent | :transient | :rate_limit
end
```

Consecuencias concretas:

- El motor de campañas pregunta `capabilities()` y decide: si `:billable`,
  aplica presupuesto y max-price; si `:presence`, divide la audiencia en
  conectados (socket) y desconectados (push).
- La capa de IA (Fase 2) pregunta `:streaming` y elige entre emitir tokens o
  esperar la respuesta completa.
- Añadir Instagram, Messenger o Telegram es **un módulo nuevo**, no una
  cirugía.

### 4.4 Principio rector Web: la memoria es caché, Postgres es la verdad

Cada sesión web vive en un proceso, pero **su fuente de verdad es Postgres**.
El proceso es una caché caliente reconstruible desde la base en cualquier
nodo. Esto elimina la necesidad de un registro de procesos distribuido
(`:global`, Horde) en Fase 1: si el cliente reconecta a otro nodo, ese nodo
rehidrata la sesión desde la base y el proceso viejo expira solo por
`:timeout`. Un breve solapamiento de dos procesos es inocuo porque **las
escrituras son idempotentes por `client_msg_id`** (§7.2).

---

## 5. Stack tecnológico

| Capa | Elección | Justificación |
|---|---|---|
| **Runtime / concurrencia** | **Elixir + OTP 27** | Aislamiento por proceso, supervisores, y **latencia de cola predecible con muchas conexiones**: con 100k+ conexiones concurrentes la p99 de Elixir se mantuvo < 20 ms mientras la de Go superó los 80 ms. Go gana ~25–30% en throughput por request; irrelevante para WA (techo de Meta) y secundario para Web (el límite son conexiones, no CPU). |
| **Sockets web** | **Phoenix Channels** + **Phoenix.Presence** | 2M conexiones en un nodo documentadas. Presence con CRDT sin base de datos externa. Cliente JS oficial con reconexión, backoff y *longpoll* fallback. |
| **PubSub** | **Phoenix.PubSub** (adaptador `:pg`) | Fan-out cluster-wide sobre distribución Erlang: **un** mensaje inter-nodo por broadcast, sin Redis. |
| **Pipelines / backpressure** | **Broadway** | Backpressure heredada de GenStage, rate limiting, batching. Un pipeline por número WA; otro para el drenaje de webhooks; otro para Web Push. |
| **Jobs durables** | **Oban** (Postgres) | ~17.700 jobs/s medidos en una M1 Pro (1M en 57 s) con *async acking* y `PartitionSupervisor`. Muy por encima de lo necesario. |
| **Base de datos** | **PostgreSQL 17** | Cola (`SKIP LOCKED`), estado, particionado, `pgvector` en Fase 2. Un motor. |
| **Cliente HTTP** | **Finch** (Mint) | Pools por host, HTTP/2. ~32 conexiones en vuelo por número WA; pool aparte por servicio de push. |
| **Web / consola** | **Phoenix LiveView** | Progreso en vivo sin API + SPA aparte. |
| **Clustering** | **libcluster** | Descubrimiento de nodos (DNS/gossip). El pinning WA lo resuelve Postgres; las sesiones web no necesitan registro global (§4.4). |
| **Protección del widget** | `check_origin` de Phoenix, **Cloudflare Turnstile** en creación de sesión anónima, límites por IP en el proxy | Somos ahora la plataforma: hay que defenderse como Meta se defiende de nosotros. |
| **Observabilidad** | **Telemetry → Prometheus + Grafana**, OpenTelemetry | Broadway, Oban, Ecto, Finch y Phoenix emiten `:telemetry` de fábrica. |
| **Despliegue** | Releases de Elixir en Docker; `docker compose` o Fly.io | Releases inmutables. |

### 5.1 Alternativas evaluadas y descartadas

| Opción | Por qué no |
|---|---|
| **n8n como núcleo** | Workflows como blobs JSON, sin tests, lógica invisible. Y para Web es directamente inviable: no sostiene conexiones persistentes. **Uso recomendado: herramienta interna de operaciones**, nunca en el camino crítico. |
| **Go** | Excelente en throughput. Pero sin supervisores ni aislamiento por proceso, el estado por sesión web y las 100k conexiones con p99 estable hay que construirlos a mano. La ventaja bruta no se cobra en ninguno de los dos canales. |
| **Node + Socket.IO / BullMQ** | Un solo hilo por proceso: un handler lento degrada la p99 de todas las conexiones de ese proceso. Escalar es multiplicar procesos y sincronizarlos vía Redis. Es exactamente el problema que el BEAM resuelve de fábrica. |
| **Kafka / RabbitMQ** | Se justifica sobre ~50k eventos/s sostenidos o replay multi-consumidor. A 2.400 eventos/s, Postgres + Broadway sobra. |
| **Redis (PubSub o rate limiting)** | PubSub lo da `:pg`; el rate limiting es local por diseño (pinning WA; sesión-en-proceso Web). Cero razones para añadirlo. |
| **Servicio gestionado de WebSockets (Pusher, Ably)** | Cobran por conexión-minuto y por mensaje. A 100k conexiones concurrentes el costo supera al de la infraestructura completa. |
| **Rust** | El rendimiento no es el problema; el costo de desarrollo sí. |
| **MongoDB** | Un motor de campañas necesita transacciones, constraints únicos y `SKIP LOCKED`. |

### 5.2 Qué pasa con la API Hono actual

El proyecto actual (`src/server.ts`, 3 módulos de rutas, 4 servicios, 4
repositorios) es pequeño. **Recomendado: portarlo a Phoenix** en días, y evitar
operar dos runtimes. Alternativa: conservarlo como servicio interno de dominio
si hay alguien dedicado a mantenerlo. Higiene pendiente: `package.json` declara
`prisma` y `@prisma/client` pero el schema se eliminó en `d9ed43f`.

---

## 6. Fase 1 — Motor de campañas WhatsApp (sin IA)

### 6.1 Modelo de datos

```sql
CREATE TYPE recipient_state AS ENUM (
  'pending','claimed','sent','delivered','read','failed','suppressed'
);

CREATE TABLE campaigns (
  id             bigserial PRIMARY KEY,
  name           text NOT NULL,
  channel        text NOT NULL,           -- whatsapp | web
  template_name  text,                    -- WA: plantilla aprobada
  template_lang  text,
  category       text,                    -- WA: marketing | utility | authentication
  sender         text NOT NULL DEFAULT 'cloud_api',  -- cloud_api | mm_lite | web
  payload        jsonb,                   -- Web: contenido del mensaje/promo
  target_mps     integer,                 -- WA: NULL = usar el del número
  max_price      numeric(10,6),           -- WA: max-price bidding
  state          text NOT NULL DEFAULT 'draft',
  scheduled_at   timestamptz,
  jitter_window  interval DEFAULT '0',    -- Web: dispersar entrega (§7.5)
  inserted_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE campaign_recipients (
  id               bigserial,
  campaign_id      bigint NOT NULL REFERENCES campaigns(id),
  address          text   NOT NULL,       -- WA: E.164 · Web: user_id o session_id
  shard_key        text   NOT NULL,       -- WA: phone_number_id · Web: 'live'|'push'
  template_vars    jsonb  NOT NULL DEFAULT '{}',
  state            recipient_state NOT NULL DEFAULT 'pending',
  external_id      text,                  -- WA: wa_message_id · Web: push receipt
  attempts         smallint NOT NULL DEFAULT 0,
  next_attempt_at  timestamptz NOT NULL DEFAULT now(),
  lease_until      timestamptz,
  last_error_code  integer,
  fbtrace_id       text,
  sent_at          timestamptz,
  delivered_at     timestamptz,
  PRIMARY KEY (id, campaign_id)
) PARTITION BY HASH (campaign_id);

-- Idempotencia estructural: imposible enviar dos veces a la misma persona
-- en la misma campaña, aunque el código falle.
CREATE UNIQUE INDEX ON campaign_recipients (campaign_id, address);

CREATE INDEX recipients_claim_idx
  ON campaign_recipients (campaign_id, shard_key, next_attempt_at)
  WHERE state = 'pending';

-- Append-only. Fuente de verdad para facturación y auditoría.
CREATE TABLE status_events (
  id             bigserial PRIMARY KEY,
  channel        text NOT NULL,
  external_id    text NOT NULL,
  status         text NOT NULL,
  occurred_at    timestamptz NOT NULL,
  pricing        jsonb,
  error          jsonb,
  raw            jsonb NOT NULL,
  received_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON status_events (channel, external_id);

CREATE TABLE suppressions (
  channel     text NOT NULL,
  address     text NOT NULL,
  reason      text NOT NULL,
  until       timestamptz,   -- NULL = permanente
  inserted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel, address)
);
```

### 6.2 Claim de lote

```sql
WITH claimed AS (
  SELECT id, campaign_id
  FROM campaign_recipients
  WHERE campaign_id = $1 AND shard_key = $2
    AND state = 'pending' AND next_attempt_at <= now()
  ORDER BY id
  FOR UPDATE SKIP LOCKED
  LIMIT $3
)
UPDATE campaign_recipients r
   SET state = 'claimed',
       lease_until = now() + interval '60 seconds',
       attempts = attempts + 1
  FROM claimed c
 WHERE r.id = c.id AND r.campaign_id = c.campaign_id
RETURNING r.id, r.address, r.template_vars;
```

`FOR UPDATE SKIP LOCKED` permite N productores sin bloqueo mutuo. El
`lease_until` es la red de seguridad: un barredor devuelve a `pending` lo que
quedó `claimed` con lease vencido.

### 6.3 El pacer: GCRA sobre `:atomics`

Un rate limiter con `Process.send_after` acumula drift y produce ráfagas.
**GCRA** (*Generic Cell Rate Algorithm*): cero timers, un entero atómico y
aritmética sobre el reloj monotónico. **El mismo módulo se reutiliza en Web
(§7.4) con el rol invertido: allí protegemos nuestro servidor de los clientes.**

```elixir
defmodule Ltp.Pacer do
  @moduledoc """
  Rate limiter GCRA lock-free. Estado: un entero atómico con el TAT
  (Theoretical Arrival Time) del próximo evento permitido, en ns monotónicos.
  `take/2` es O(1), no asigna memoria y no involucra al scheduler.
  """

  # Ráfaga tolerada: 100 ms de crédito acumulable.
  @burst_ns 100_000_000

  def new, do: :atomics.new(1, signed: true)

  @doc "Devuelve :ok si se puede proceder ya, o {:wait, µs} hasta el próximo slot."
  def take(ref, rate_per_s) do
    interval_ns = div(1_000_000_000, rate_per_s)
    take(ref, interval_ns, System.monotonic_time(:nanosecond), 0)
  end

  defp take(_ref, interval_ns, _now, tries) when tries > 64 do
    {:wait, div(interval_ns, 1_000)}
  end

  defp take(ref, interval_ns, now, tries) do
    prev = :atomics.get(ref, 1)
    base = max(prev, now - @burst_ns)
    tat  = base + interval_ns

    cond do
      tat - now > @burst_ns ->
        {:wait, div(tat - now, 1_000)}

      :atomics.compare_exchange(ref, 1, prev, tat) == :ok ->
        :ok

      true ->
        take(ref, interval_ns, System.monotonic_time(:nanosecond), tries + 1)
    end
  end
end
```

### 6.4 Pipeline por número

```elixir
defmodule Ltp.Sender.Pipeline do
  use Broadway

  def start_link(%{phone_number_id: pid, mps: mps} = opts) do
    Broadway.start_link(__MODULE__,
      name: via(pid),
      producer: [
        module: {Ltp.Sender.Producer, opts},
        concurrency: 1,
        rate_limiting: [allowed_messages: mps, interval: 1_000]
      ],
      processors: [
        # ~32 peticiones en vuelo: mps * p99_latencia(0,4 s).
        default: [concurrency: max(8, ceil(mps * 0.4)), max_demand: 10]
      ],
      batchers: [
        db: [concurrency: 2, batch_size: 200, batch_timeout: 250]
      ],
      context: opts
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{data: recipient} = msg, ctx) do
    case ctx.channel.deliver(recipient, ctx) do
      {:ok, ext_id}          -> msg |> put_result({:sent, ext_id}) |> mark_batcher()
      {:error, %{class: :rate_limit}}          -> Broadway.Message.failed(msg, :rate_limit)
      {:error, %{class: :permanent} = e}       -> msg |> put_result({:failed, e}) |> mark_batcher()
      {:error, %{class: :transient} = e}       -> Broadway.Message.failed(msg, {:retry, e})
    end
  end

  @impl true
  def handle_batch(:db, messages, _info, _ctx) do
    Ltp.Campaigns.bulk_ack(messages)
    messages
  end

  defp via(pid), do: {:via, Registry, {Ltp.Senders, pid}}
end
```

Un pipeline por número = aislamiento real. ACK por lotes de 200: la diferencia
entre 80 MPS cómodos y 80 MPS con contención de pool. Tres clases de error con
política distinta cada una.

### 6.5 Idempotencia y garantía de entrega

La Cloud API no ofrece clave de idempotencia nativa: la garantía honesta es
**at-least-once**, convertida en *effectively-once* con tres capas:

1. **Constraint único** `(campaign_id, address)`.
2. **Claim-then-send con lease.**
3. **Reconciliación por webhook** antes de reintentar una fila con
   `attempts > 0` y sin `external_id`.

Objetivo medido: < 1 duplicado por millón.

### 6.6 Ingestor de webhooks

```elixir
defmodule LtpWeb.WebhookController do
  use LtpWeb, :controller

  # Cero trabajo de negocio en el camino de la petición: validar, bufferizar, ack.
  def receive(conn, _params) do
    raw = conn.assigns.raw_body

    if valid_signature?(raw, get_req_header(conn, "x-hub-signature-256")) do
      :ets.insert(:webhook_buffer, {System.unique_integer([:monotonic]), raw})
      send_resp(conn, 200, "")
    else
      send_resp(conn, 401, "")
    end
  end

  defp valid_signature?(raw, ["sha256=" <> sig]) do
    expected = :crypto.mac(:hmac, :sha256, app_secret(), raw) |> Base.encode16(case: :lower)
    :crypto.hash_equals(expected, sig)   # tiempo constante
  end

  defp valid_signature?(_, _), do: false
end
```

Un Broadway drena el ETS cada 50 ms e inserta con `COPY` por lotes: bajo
2.400 eventos/s, ~20 escrituras/s a Postgres en vez de 2.400.

> **Compromiso consciente:** el buffer ETS es volátil; un crash entre el ack y
> el flush pierde ~50 ms de eventos. Se acepta porque son reconstruibles
> consultando el estado del mensaje, y la alternativa síncrona rompe el SLO de
> ack y provoca reintentos de Meta. Variante si no se acepta: `COPY` síncrono
> a tabla *unlogged* de staging.

### 6.7 Circuit breaker por calidad

```
Verde     → MPS objetivo
Amarillo  → 50% del MPS, alerta, pausar marketing de baja prioridad
Rojo      → pausa de TODO marketing en ese número; solo utility/auth; escalar
```

Alimentado por `phone_number_quality_update` y `account_alerts`.

### 6.8 Warm-up y mantenimiento de tier

Scheduler de Oban cada 6 h: verifica tier; si el consumo de 7 días < 50% del
límite, programa envíos de mantenimiento; para números nuevos ejecuta la rampa
250 → 2.000 → 10.000 → 100.000 vigilando calidad en cada escalón.

---

## 7. Fase 1 — Canal Web de alta concurrencia (sin IA)

Aquí no hay tercero. Todo lo que sigue es responsabilidad nuestra.

### 7.1 Qué hace el canal web antes de tener IA

Que la Fase 1 no lleve IA no significa que el widget esté vacío. Sin un modelo
detrás, el canal web entrega:

- **Flujos guiados** (menús, botones, formularios): "¿Qué necesitas? → Planes /
  Comisiones / Estado de mi pago". Determinista, sub-100 ms, cero costo.
- **FAQ por intención simple**: matching por palabras clave o por caché
  semántico precalculado (§8.2) sobre las preguntas frecuentes.
- **Captura de leads** y agendamiento.
- **Recepción de campañas**: promos en vivo a conectados, Web Push a
  desconectados, bandeja *in-app* persistente.
- **Handoff a agente humano** (opcional, decisión abierta §13): la sesión ya
  existe; conectar una consola de agente es un canal más.

Todo esto ejercita **el 100% de la infraestructura de sesiones, sockets y
fan-out** antes de añadir la carga de IA. Cuando llegue la Fase 2, el modelo se
enchufa a una sesión que ya ha sobrevivido a producción.

### 7.2 Sesión: proceso + fuente de verdad en Postgres

```sql
CREATE TABLE web_sessions (
  id            uuid PRIMARY KEY,
  user_id       bigint,                      -- NULL = anónima
  tier          text NOT NULL DEFAULT 'anon', -- anon | identified | verified
  origin        text NOT NULL,
  last_seq      bigint NOT NULL DEFAULT 0,
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  inserted_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE web_messages (
  session_id    uuid NOT NULL REFERENCES web_sessions(id),
  seq           bigint NOT NULL,             -- monotónico por sesión
  direction     text NOT NULL,               -- in | out
  client_msg_id uuid,                        -- idempotencia de entrada
  body          jsonb NOT NULL,
  inserted_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, seq)
) PARTITION BY RANGE (inserted_at);          -- particiones mensuales, retención

-- El mismo client_msg_id nunca produce dos mensajes, aunque el cliente
-- reintente o dos nodos solapen la sesión durante una reconexión.
CREATE UNIQUE INDEX ON web_messages (session_id, client_msg_id)
  WHERE client_msg_id IS NOT NULL;
```

```elixir
defmodule Ltp.Web.Session do
  @moduledoc """
  Un proceso por sesión web. Caché caliente del estado conversacional:
  ring buffer de los últimos @ring mensajes para resume, máquina de estados
  del flujo guiado, y el pacer GCRA que limita al cliente.

  La fuente de verdad es Postgres: este proceso se puede rehidratar en
  cualquier nodo. Expira solo tras @idle sin actividad.
  """
  use GenServer, restart: :transient

  @ring 200
  @idle :timer.minutes(30)

  def start_link(session_id),
    do: GenServer.start_link(__MODULE__, session_id, name: via(session_id))

  def via(id), do: {:via, Registry, {Ltp.Web.Sessions, id}}

  @impl true
  def init(session_id) do
    # Rehidratación desde la base: cabecera + últimos @ring mensajes.
    {:ok, Ltp.Web.Store.load(session_id, @ring) |> Map.put(:pacer, Ltp.Pacer.new()), @idle}
  end

  @doc "Mensaje entrante del cliente. Idempotente por client_msg_id."
  def handle_call({:inbound, %{client_msg_id: cid} = msg}, _from, s) do
    cond do
      MapSet.member?(s.seen, cid) ->
        {:reply, {:ok, :duplicate}, s, @idle}

      Ltp.Pacer.take(s.pacer, s.rate_for_tier) != :ok ->
        {:reply, {:error, :rate_limited}, s, @idle}

      true ->
        {:ok, seq} = Ltp.Web.Store.append(s.id, :in, msg)
        s = s |> remember(cid) |> push_ring({seq, :in, msg})
        outbound = Ltp.Web.Flow.step(s, msg)             # flujo guiado (Fase 1)
        s = Enum.reduce(outbound, s, &emit(&2, &1))
        {:reply, {:ok, seq}, s, @idle}
    end
  end

  @doc "Resume tras reconexión: todo lo posterior a last_seq que el cliente vio."
  def handle_call({:resume, last_seq}, _from, s) do
    missed =
      case Enum.filter(s.ring, fn {seq, _, _} -> seq > last_seq end) do
        []    when last_seq < s.last_seq - @ring -> Ltp.Web.Store.after(s.id, last_seq)
        local -> local
      end
    {:reply, {:ok, missed}, s, @idle}
  end

  @impl true
  def handle_info(:timeout, s), do: {:stop, :normal, s}

  defp emit(s, body) do
    {:ok, seq} = Ltp.Web.Store.append(s.id, :out, body)
    Phoenix.PubSub.broadcast(Ltp.PubSub, "session:#{s.id}", {:out, seq, body})
    push_ring(s, {seq, :out, body})
  end

  defp push_ring(s, entry), do: %{s | ring: Enum.take([entry | s.ring], @ring), last_seq: elem(entry, 0)}
  defp remember(s, cid),    do: %{s | seen: MapSet.put(s.seen, cid)}
end
```

Puntos de diseño:

- **`restart: :transient` + `:timeout`**: el proceso muere solo por
  inactividad; el supervisor no lo resucita. Con 100k sesiones activas y
  200k inactivas, solo pagas memoria por las 100k.
- **Ring buffer de 200**: cubre el 99% de las reconexiones sin tocar la base.
  El 1% restante (cliente que vuelve tras horas) cae a Postgres.
- **`seen` como `MapSet` acotado** (no mostrado: se poda con el ring).
- **El socket no es la sesión.** Un socket es efímero; la sesión sobrevive a
  N sockets. Esto es lo que hace trivial la reconexión y el multi-pestaña.

### 7.3 El canal (socket): autorización, backpressure, límites

```elixir
defmodule LtpWeb.ChatChannel do
  use LtpWeb, :channel

  # El join es la ÚNICA puerta. Un topic no autorizado aquí es inalcanzable.
  @impl true
  def join("session:" <> id, %{"token" => token, "last_seq" => last_seq}, socket) do
    with {:ok, ^id} <- Phoenix.Token.verify(socket, "session", token, max_age: 86_400),
         {:ok, pid}  <- Ltp.Web.Sessions.ensure(id),
         {:ok, missed} <- GenServer.call(pid, {:resume, last_seq}) do
      Phoenix.PubSub.subscribe(Ltp.PubSub, "session:#{id}")
      send(self(), {:replay, missed})
      {:ok, assign(socket, session_id: id, session: pid, outq: 0)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("msg", %{"client_msg_id" => _} = msg, socket) do
    case GenServer.call(socket.assigns.session, {:inbound, atomize(msg)}, 5_000) do
      {:ok, seq}                -> {:reply, {:ok, %{seq: seq}}, socket}
      {:error, :rate_limited}   -> {:reply, {:error, %{reason: "slow_down"}}, socket}
    end
  end

  # Backpressure por socket: si el cliente no drena, no acumulamos sin límite.
  @max_outq 500
  @impl true
  def handle_info({:out, seq, body}, %{assigns: %{outq: q}} = socket) when q < @max_outq do
    push(socket, "out", %{seq: seq, body: body})
    {:noreply, assign(socket, :outq, q + 1)}
  end

  def handle_info({:out, _seq, _body}, socket) do
    # Cliente lento: se le pide resync y se descarta el push. La sesión
    # conserva todo en el ring/Postgres, así que no se pierde nada.
    push(socket, "resync", %{})
    {:noreply, socket}
  end

  def handle_info({:replay, missed}, socket) do
    Enum.each(missed, fn {seq, :out, body} -> push(socket, "out", %{seq: seq, body: body}) end)
    {:noreply, socket}
  end

  # El cliente confirma consumo; se decrementa la cola virtual.
  def handle_in("ack", %{"seq" => _}, socket),
    do: {:noreply, update_in(socket.assigns.outq, &max(&1 - 1, 0))}
end
```

Y en el `Endpoint`:

```elixir
socket "/socket", LtpWeb.UserSocket,
  websocket: [
    timeout: 60_000,                 # > heartbeat del cliente (30 s)
    max_frame_size: 64 * 1024,       # 64 KB: nadie manda un PDF por el chat
    compress: true,
    check_origin: {LtpWeb.Origins, :allowed?, []}   # allowlist dinámica de dominios cliente
  ],
  longpoll: [timeout: 60_000]        # fallback para proxies corporativos
```

### 7.4 Rate limiting por cliente: el pacer invertido

En WhatsApp `Ltp.Pacer` nos frena para no exceder a Meta. En Web **frena al
cliente para que no nos exceda a nosotros**, y vive dentro del proceso de
sesión: **cero coordinación, cero Redis**.

| Tier | Mensajes/s | Ráfaga | Sesiones por IP |
|---|---:|---:|---:|
| `anon` | 2 | 5 | 5 |
| `identified` | 5 | 10 | 20 |
| `verified` | 10 | 20 | 50 |

El límite por IP se aplica **en el proxy** (Caddy/Cloudflare), no en la app:
una conexión rechazada en el borde cuesta cero procesos.

> Aislamiento garantizado por construcción: un cliente que satura su pacer solo
> bloquea *su* proceso. Los otros 99.999 no comparten ni un lock con él.

### 7.5 Campañas en Web: conectados y desconectados

Una campaña web divide la audiencia en dos poblaciones con dos mecanismos:

**a) Conectados ahora → fan-out por PubSub.**

```elixir
# Topics por segmento, no un topic global: un broadcast solo despierta
# los procesos que deben recibirlo.
Phoenix.PubSub.broadcast(Ltp.PubSub, "segment:#{segment_id}",
  {:campaign, campaign_id, payload, deliver_at: jittered(now, campaign.jitter_window)})
```

- Cada sesión se suscribe al `join` a sus topics de segmento (por plan,
  región, comportamiento).
- **`jitter_window`**: 100k sockets recibiendo el mismo payload en el mismo
  milisegundo es una ráfaga de escrituras autoinfligida. Cada sesión difiere
  la entrega un tiempo aleatorio dentro de la ventana (p. ej. 30 s). Es la
  versión web del pacer.
- **Presence** distingue conectado/desconectado sin consultar la base.

**b) Desconectados → Web Push (VAPID) + bandeja in-app.**

```sql
CREATE TABLE push_subscriptions (
  id          bigserial PRIMARY KEY,
  user_id     bigint,
  session_id  uuid,
  endpoint    text NOT NULL UNIQUE,        -- URL del push service (FCM/Mozilla/Apple)
  p256dh      text NOT NULL,
  auth        text NOT NULL,
  ua_family   text,
  failures    smallint NOT NULL DEFAULT 0,
  inserted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inbox_items (                 -- la promo no se pierde si no hay push
  user_id     bigint NOT NULL,
  campaign_id bigint NOT NULL,
  payload     jsonb NOT NULL,
  read_at     timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, campaign_id)
);
```

- Web Push sí depende de terceros (los push services de cada navegador), pero
  con límites laxos y **sin tarifa**. Se envía por un pipeline Broadway con
  pool Finch por servicio; `410 Gone` → borrar suscripción; 3 fallos → marcar.
- **La bandeja in-app es la garantía**: si el usuario no tiene push, la promo
  lo espera en el widget la próxima vez que abra.
- El mismo `campaign_recipients` con `shard_key = 'live' | 'push'` reutiliza
  el claim, el lease y la idempotencia del motor WA. **Un solo motor de
  campañas, dos canales.**

### 7.6 Aritmética de fan-out y por qué no necesita Redis

Con Phoenix.PubSub sobre `:pg`, un broadcast cuesta **1 mensaje por nodo** más
los envíos locales. Con 5 nodos y 500k sockets:

```
Inter-nodo:  5 mensajes            (despreciable)
Local:       100k sends por nodo   (BEAM: microsegundos cada uno)
Socket:      100k writes por nodo  (límite real: syscalls, ~100–300k/s)
Total:       < 1 s por nodo, en paralelo → < 1 s global + jitter_window
```

Con Redis PubSub el costo de la capa de mensajería sería el mismo, pero
añadirías un sistema más, un punto único de fallo y un salto de red en el
camino de cada broadcast. **No hay caso.**

### 7.7 Protección: ahora somos la plataforma

| Amenaza | Defensa | Dónde |
|---|---|---|
| Embebido del widget en dominios ajenos | `check_origin` con allowlist por cliente | Endpoint |
| Bots creando sesiones anónimas | Cloudflare Turnstile en la emisión del token | Creación de sesión |
| Flood de conexiones desde una IP | Límite de conexiones/s y concurrentes por IP | Proxy (Caddy/Cloudflare) |
| Flood de mensajes en una sesión | Pacer GCRA por tier (§7.4) | Proceso de sesión |
| Payloads gigantes | `max_frame_size` 64 KB, validación de esquema | Socket + Channel |
| Suscripción a topics ajenos | Autorización exclusiva en `join/3`; topics derivados del token, nunca del cliente | Channel |
| Cliente lento / *slowloris* de salida | Cola de salida acotada + `resync` (§7.3) | Channel |
| Reconexión masiva tras caída de nodo | Backoff exponencial con jitter en el cliente JS oficial; el proxy limita conexiones/s | Cliente + proxy |
| Enumeración de sesiones | IDs `uuid v4` + token firmado con `max_age` | Token |

### 7.8 El widget

- Un `<script async>` servido desde CDN (Cloudflare en frente de R2), **< 50 KB
  gzip**, que monta un `<iframe>` con origen nuestro: aísla CSS y CSP del sitio
  anfitrión y evita que el DOM del cliente lea el chat.
- Cliente `phoenix` JS oficial: reconexión con backoff, heartbeat, *longpoll*
  fallback, multiplexación de topics en un socket.
- Persistencia local de `session_id`, `token` y `last_seq` para el resume.
- `client_msg_id` generado en cliente (`crypto.randomUUID()`), reenviado igual
  en cada reintento.

---

## 8. Fase 2 — Capa conversacional con IA

Se construye **encima** del mismo núcleo. La sesión como proceso (§7.2) **ya
existe y ya sobrevivió a producción**: la IA es un `Ltp.Web.Flow.step/2`
distinto, no una arquitectura nueva.

### 8.1 Streaming: la ventaja decisiva del canal web

WhatsApp **no soporta streaming**: se envía un mensaje completo. Web sí. Con
`capabilities()` declarando `:streaming`, la sesión emite tokens a medida que
el modelo los produce y el usuario ve la respuesta *aparecer* en < 300 ms
aunque tarde 2 s en completarse. **La misma respuesta, en WhatsApp, se
percibe como 2 s de espera; en Web, como instantánea.**

Implicación de infraestructura: una generación en curso vive en el proceso de
sesión. Si el cliente reconecta a otro nodo a mitad de stream, pierde tokens.
Dos remedios, en orden de simplicidad: (1) el resume por `seq` reenvía la
respuesta completa persistida al terminar; (2) *sticky sessions* en el proxy
por cookie de sesión, solo si (1) resulta insuficiente en la práctica.

### 8.2 RAG con pgvector y caché semántico

Corpus de PDFs de planes y comisiones: cientos o miles de chunks → **pgvector**,
no Qdrant. **Embeddings locales con Bumblebee/Nx** en el mismo nodo: elimina
50–150 ms de round-trip por consulta. **Caché semántico en ETS**: el 80% de las
preguntas son las mismas; resolverlas sin tocar el LLM es lo que produce
sub-100 ms — en ambos canales, y en Web ya desde la Fase 1 (§7.1).

### 8.3 OCR de comprobantes: la IA no decide sobre dinero

```
imagen → S3 → modelo de visión (extrae texto)
        → parseo determinista (regex sobre código de operación)
        → match exacto contra ventas: código + monto + fecha
        → coincidencia exacta y confianza > umbral → aprobado
          cualquier otro caso → revisión humana
```

En Web además: el usuario **arrastra la imagen al widget** (subida directa a
S3 con URL prefirmada, nunca por el socket), y la respuesta llega en streaming.

### 8.4 El canal web como palanca de costo de la IA

Desde el **2026-10-01** las respuestas de IA dentro de la ventana de 24 h en
WhatsApp son facturables por Meta. En Web cuestan **cero** en mensajería. La
estrategia de producto se deduce sola: **usar WhatsApp para captar y notificar
(plantillas, campañas) y llevar la conversación larga con IA al web** con un
deep link que abre el widget con la sesión ya autenticada. Cada conversación
que migra al web es tarifa que no se paga.

---

## 9. Observabilidad

### 9.1 WhatsApp

| Métrica | Tipo | Alerta |
|---|---|---|
| `wa_mps_efectivo{phone_number_id}` | gauge | < 90% del objetivo por > 60 s |
| `wa_errores_130429_total` | counter | **cualquier incremento** |
| `wa_webhook_ack_duration` | histogram | p99 > 50 ms |
| `wa_lag_reconciliacion` | gauge | p99 > 5 s |
| `wa_quality_rating{phone_number_id}` | gauge | cualquier cambio |
| `wa_tier_actual{phone_number_id}` | gauge | cualquier bajada |
| `campaign_tasa_entrega{campaign_id}` | gauge | < 85% |
| `campaign_costo_acumulado{campaign_id}` | counter | > presupuesto × 0,8 |

`costo_acumulado` viene del objeto `pricing` de los webhooks: costo **real**,
no estimado. Permite cortar una campaña antes de que se salga del presupuesto.

### 9.2 Web

| Métrica | Tipo | Alerta |
|---|---|---|
| `web_conexiones_activas{node}` | gauge | > 80% del objetivo por nodo |
| `web_sesiones_vivas{node}` | gauge | crecimiento sin conexiones = fuga de procesos |
| `web_join_duration` | histogram | p99 > 200 ms |
| `web_respuesta_guiada_duration` | histogram | p99 > 100 ms |
| `web_fanout_duration{campaign_id}` | histogram | > 2 s al último socket |
| `web_resync_total` | counter | pico = clientes lentos o fan-out mal dimensionado |
| `web_rate_limited_total{tier}` | counter | pico = ataque o límite mal calibrado |
| `web_reconexiones_por_s` | gauge | pico = caída de nodo o red |
| `web_push_entregados / fallidos` | counter | tasa de fallo > 10% |
| `beam_memoria_por_sesion` | gauge | > 40 KB = revisar ring/estado |
| `beam_run_queue` | gauge | > núcleos × 2 sostenido = saturación de scheduler |

Trazas OpenTelemetry con `fbtrace_id` (WA) y `session_id` (Web) como atributos.

---

## 10. Infraestructura

```
┌── Cloudflare (CDN widget, WAF, Turnstile, límite de conexiones por IP) ──┐
│                                                                          │
│  ┌── Caddy (TLS, HTTP/2, WebSocket, idle timeout > heartbeat) ────────┐  │
│  │                                                                    │  │
│  │  ┌── nodo-1 (release) ──┐  ┌── nodo-2 ──┐  ┌── nodo-3 ──┐          │  │
│  │  │ · ingestor WA        │  │  idem      │  │  idem      │          │  │
│  │  │ · pipelines núm A,B  │  │  C,D       │  │  E,F       │          │  │
│  │  │ · ~100k sockets web  │  │  ~100k     │  │  ~100k     │          │  │
│  │  │ · LiveView           │  │            │  │            │          │  │
│  │  └──────────────────────┘  └────────────┘  └────────────┘          │  │
│  │              libcluster (DNS)  ·  Phoenix.PubSub (:pg)             │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │
                   PostgreSQL 17 (primario + réplica) + PgBouncer
```

**Dimensionamiento inicial:** 2 nodos de 4 vCPU / 16 GB — redundancia, no
capacidad: cada uno sostiene ~100k sesiones web y todo el tráfico WA. Se añade
un tercer nodo cuando `web_conexiones_activas` supere el 60% sostenido en dos.
Postgres 4 vCPU / 16 GB, NVMe, WAL en volumen separado.

**Ajustes de SO obligatorios para conexiones persistentes** (sin ellos el techo
es ~1k conexiones, no 100k):

```
ulimit -n 1048576                 # descriptores por proceso
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
```

Y en el `vm.args` del release: `+P 2000000` (procesos máximos), `+Q 1048576`
(puertos máximos).

**El balanceador no necesita *sticky sessions*** en Fase 1: la sesión se
rehidrata en cualquier nodo desde Postgres (§4.4). Se activan solo si el
streaming de IA lo exige (§8.1).

Sin Redis. Sin Kafka. Sin n8n en el camino crítico.

---

## 11. Plan de ejecución

| Fase | Entregable | Criterio de salida |
|---|---|---|
| **0 — Fundación** | Esqueleto Phoenix, esquema, CI, releases, staging, ajustes de SO | Despliegue reproducible; `ulimit` verificado en el nodo |
| **1 — Ingestor WA** | Webhooks con firma, buffer, `COPY` por lotes | 5.000 eventos/s sintéticos, ack p99 < 50 ms |
| **2 — Emisor WA** | Pipeline Broadway + pacer + clasificación de errores | 80 MPS × 10 min contra mock, **0× 130429** |
| **3 — Núcleo Web** | Sockets, sesiones, resume, pacer por tier, widget en CDN | **100k conexiones/nodo** en prueba de carga; reconexión masiva absorbida < 60 s |
| **4 — Campañas** | Motor unificado (WA + Web live + Web Push), segmentos, consola LiveView | Campaña de 10k en staging por ambos canales con reconciliación completa |
| **5 — Producción WA** | 1 número real, rampa de tier, alertas, runbook | Campaña real de 2k, entrega > 90% |
| **6 — Producción Web** | Widget en el sitio real, Turnstile, WAF | 1 semana sin incidentes de abuso; p99 dentro de SLO |
| **7 — Escala WA** | Multi-número, pinning, failover | 100k en < 22 min; failover sin duplicados |
| **8 — MM Lite** | Adaptador, A/B contra Cloud API | Comparativa medida de entrega |
| **9 — IA en Web** | Streaming, RAG + pgvector, caché semántico, OCR | p50 primer token < 300 ms; **caso de negocio validado sin tarifa de Meta** |
| **10 — IA en WhatsApp** | Mismo `Flow` sin streaming | Solo si el caso de negocio post 2026-10-01 lo justifica |

**La IA llega primero al web, no a WhatsApp.** Es más barata (cero tarifa),
mejor (streaming) y no depende de la revalidación económica del 2026-10-01.

---

## 12. Modelo de costos

### 12.1 WhatsApp — fórmula, no cifra

```
Costo_mensual_WA =   M_marketing × P_marketing(PE)
                   + M_utility   × P_utility(PE)
                   + M_auth      × P_auth(PE)
                   + M_servicio  × P_servicio(PE)     ← 0 hasta 2026-09-30
```

Parámetros del rate card vigente de Meta para Perú (PEN). Palancas: tiers de
volumen, max-price bidding, MM Lite (no paga filtrados), reclasificar a
Utility lo genuinamente transaccional, higiene de lista.

### 12.2 Web — cero por mensaje; se paga en conexiones

| Concepto | USD/mes |
|---|---:|
| Mensajería (sockets, push, in-app) | **0** |
| Cloudflare (CDN + WAF + Turnstile, plan Pro) | 20–25 |
| Nodo adicional por cada ~100k sesiones concurrentes | 40–60 |

### 12.3 Infraestructura común

| Concepto | USD/mes |
|---|---:|
| 2 × VPS 4 vCPU / 16 GB | 80–120 |
| PostgreSQL gestionado 4 vCPU / 16 GB | 60–100 |
| S3 / Cloudflare R2 | 5–10 |
| Cloudflare Pro | 20–25 |
| Observabilidad (self-hosted) | incluido |
| **Subtotal** | **165–255** |

**Lectura estratégica:** cada conversación que se mueve de WhatsApp a Web pasa
de costo marginal positivo a costo marginal cero. Con la tarifa del
2026-10-01, la infraestructura web se amortiza con el ahorro de mensajería.

---

## 13. Riesgos y decisiones abiertas

| Riesgo | Canal | Impacto | Mitigación |
|---|---|---|---|
| Caída de quality rating → pérdida de tier | WA | Alto | Circuit breaker (§6.7); rotación de números; higiene |
| Retiro de marketing en Cloud API | WA | Alto | Adaptador MM Lite desde el día uno (§2.3) |
| Cambio tarifario 2026-10-01 | WA | Medio-Alto | Llevar la IA al web primero (§8.4) |
| Tormenta de fan-out (500k en el mismo ms) | Web | Medio | `jitter_window` (§7.5); topics por segmento |
| Fuga de procesos de sesión | Web | Medio | `:timeout` + `restart: :transient`; métrica `web_sesiones_vivas` |
| Bots en sesiones anónimas | Web | Medio | Turnstile + tiers + límite por IP en el borde (§7.7) |
| *Thundering herd* tras caída de nodo | Web | Medio | Backoff con jitter en cliente; límite conexiones/s en proxy |
| Ventana de pérdida del buffer ETS | WA | Bajo | Aceptada (§6.6); alternativa documentada |
| Bloqueo de marketing a `+1` | WA | Bajo | Excluir en segmentador |
| Equipo sin experiencia en Elixir | Ambos | **Alto** | **Decisión abierta** |

### Decisiones que requieren respuesta del negocio

1. **Volumen real objetivo por canal.** WA: destinatarios por campaña y
   campañas por mes. Web: sesiones concurrentes en pico esperadas (¿10k?
   ¿100k? ¿500k?). Bajo 50k por campaña y bajo 10k concurrentes, parte de
   este diseño es sobre-ingeniería y hay que simplificar.
2. **Cuántos números de WhatsApp** se pueden conseguir y verificar.
3. **¿Handoff a agente humano en Fase 1?** Cambia el alcance de la consola.
4. **¿Sesiones web anónimas o siempre autenticadas?** Anónimas amplían el
   embudo y multiplican la superficie de abuso.
5. **Experiencia del equipo en Elixir.** El mayor riesgo del plan, y no es
   técnico. Si nadie más que una persona lo puede mantener, **Go es la
   elección correcta** para WhatsApp — pero para el canal web a 100k+
   conexiones con p99 estable, Go exige construir a mano lo que el BEAM
   trae de fábrica, y ese costo hay que ponerlo sobre la mesa.
6. **Destino de la API Hono:** portar o conservar (§5.2).

---

## 14. Fuentes

Investigación realizada el 2026-09-17/18. Tarifas y límites cambian con
frecuencia; verificar contra la documentación oficial antes de decisiones
financieras.

**Plataforma Meta / WhatsApp**
- Messaging Limits — https://developers.facebook.com/documentation/business-messaging/whatsapp/messaging-limits
- Pricing — https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing
- Error codes — https://developers.facebook.com/documentation/business-messaging/whatsapp/support/error-codes
- Rate Limits & Throughput (2026) — https://helo.ai/resources/blog/whatsapp-api-rate-limits
- Messaging Limits 2026 — https://chatarmin.com/en/blog/whats-app-messaging-limits
- Error 130429 — https://dualhook.com/docs/whatsapp-error-130429
- MM Lite API — https://www.infobip.com/docs/whatsapp/mm-lite
- MM Lite: alcance — https://m.aisensy.com/blog/marketing-messages-lite-api/
- Pricing 2026 por categoría — https://blueticks.co/blog/whatsapp-business-pricing-categories-2026-utility-marketing-authentication
- Pricing mundial 2026/2027 — https://sleekflow.io/blog/whatsapp-business-price

**Canal Web / Phoenix**
- The Road to 2 Million Websocket Connections in Phoenix — https://www.phoenixframework.org/blog/the-road-to-2-million-websocket-connections
- Reproducción del benchmark — https://github.com/dsander/phoenix-connection-benchmark
- Phoenix Channels (docs) — https://hexdocs.pm/phoenix/channels.html
- Phoenix.PubSub (docs) — https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html
- PubSub Broadcast Performance — https://elixirforum.com/t/pubsub-broadcast-performance-and-best-practice/60175

**Stack y rendimiento**
- Broadway — https://elixir-broadway.org/
- Oban — https://github.com/oban-bg/oban
- One Million Jobs a Minute with Oban — https://oban.pro/articles/one-million-jobs-a-minute-with-oban
- BullMQ vs Oban — https://bullmq.io/articles/benchmarks/bullmq-elixir-vs-oban/
- Go vs Node vs Elixir — https://stressgrid.com/blog/benchmarking_go_vs_node_vs_elixir/
- Elixir vs Go 2026 — https://equantra.in/blog/elixir-vs-go-2026
- Observing low latency in Phoenix — https://www.theerlangelist.com/article/phoenix_latency
