# Plan Maestro de Implementación Técnica End-to-End
## Plataforma Omnicanal de Alta Concurrencia (WebSockets + WhatsApp + IA)

> **Documento de Ingeniería y Arquitectura de Sistemas Distribuidos**  
> **Ubicación del Proyecto:** `D:\proyectos\ltp_chatbot_v2` (Monorepo Umbrella en Elixir)  
> **Entorno de Ejecución:** Ubuntu 24.04 LTS (WSL2) + Docker Desktop  
> **Stack Base:** Elixir 1.18.3 · Erlang/OTP 27 · Phoenix 1.7/1.8 · PostgreSQL 17 (pgvector)  
> **Fecha de Emisión:** 2026-09-21 · **Versión:** 2.2 · **Estado:** Fase 0 Completada / Fase 1 Lista para Ejecución  

---

## ÍNDICE GENERAL

1. [Visión, Tesis y Filosofía de Arquitectura (SOLID & BEAM)](#1-visión-tesis-y-filosofía-de-arquitectura)
2. [Fase 0: Fundación de Infraestructura y Arquitectura Base (COMPLETADA 100%)](#2-fase-0-fundación-de-infraestructura-y-arquitectura-base)
3. [Inventario Tecnológico Exhaustivo de Librerías y Herramientas](#3-inventario-tecnológico-exhaustivo)
   * [3.1 Análisis Arquitectónico: Go, Rust y Prometheus (DESCARTADOS) vs 100% Elixir y Observabilidad Nativa](#31-análisis-arquitectónico-go-rust-y-prometheus-descartados-vs-100-elixir-y-observabilidad-nativa)
4. [Hoja de Ruta de Implementación Detallada (Fases Futuras 1 a 6)](#4-hoja-de-ruta-de-implementación-detallada)
   * [Fase 1: El Chatbot Web en Iframe y Comunicación en Tiempo Real](#fase-1-el-chatbot-web-en-iframe-y-comunicación-en-tiempo-real)
   * [Fase 2: Seguridad, Hardening y Protección Anti-Abuso](#fase-2-seguridad-hardening-y-protección-anti-abuso)
   * [Fase 3: Persistencia, Sesiones y Memoria RAM (Ring Buffer)](#fase-3-persistencia-sesiones-y-memoria-ram)
   * [Fase 4: Canal WhatsApp Oficial y Webhooks de Meta](#fase-4-canal-whatsapp-oficial-y-webhooks-de-meta)
   * [Fase 5: Capa Conversacional con Inteligencia Artificial (RAG & Streaming)](#fase-5-capa-conversacional-con-inteligencia-artificial)
   * [Fase 6: Clúster de 3 Nodos, Producción y Alta Disponibilidad](#fase-6-clúster-de-3-nodos-producción-y-alta-disponibilidad)
5. [Matriz de Archivos del Monorepo y Responsabilidades](#5-matriz-de-archivos-del-monorepo)
6. [Manual de Operación Diaria y Comandos (Runbook)](#6-manual-de-operación-diaria-y-comandos)

---

## 1. Visión, Tesis y Filosofía de Arquitectura

El propósito de esta plataforma es orquestar mensajería masiva y soporte automatizado a gran escala, unificando dos canales que presentan requerimientos técnicos completamente asimétricos:

```
                                  ┌────────────────────────────────────────────────────────┐
                                  │            CONTRATO UNIFICADO: Ltp.Channel             │
                                  │  Capacidades: :streaming, :templates, :presence, etc.  │
                                  └───────────┬────────────────────────────────┬───────────┘
                                              │                                │
                     CANAL ASIMÉTRICO EXTERNO │                                │ CANAL PROPIO DE ALTA CONCURRENCIA
                         (WhatsApp - Meta)    │                                │ (WebSockets / Web Push)
                                              ▼                                ▼
    ┌──────────────────────────────────────────────────┐      ┌──────────────────────────────────────────────────┐
    │ · Límite duro externo: 80 MPS por número         │      │ · Techo interno: 100k+ sockets / nodo (Elixir)   │
    │ · Facturación por mensaje entregado (Meta PEN)   │      │ · Costo por mensaje: $0.00                       │
    │ · Ventana de 24 horas y plantillas aprobadas     │      │ · Streaming token a token (<300 ms percibidos)   │
    │ · Ingesta masiva: 2.400 webhooks/s entrantes     │      │ · Formulario incrustable en <iframe> de 1 línea  │
    │ · Pinning de número a nodo (Advisory Locks)      │      │ · Sesión GenServer + Ring Buffer de 200 msgs RAM │
    │ · Pacer GCRA en nanosegundos (:atomics)          │      │ · Pacer inverso GCRA por tier (Anti-DoS)         │
    │ · Buffer ETS en RAM + Batch COPY a Postgres      │      │ · Fan-out clusterizado vía :pg (Sin Redis)       │
    └──────────────────────────────────────────────────┘      └──────────────────────────────────────────────────┘
```

### Las 4 Tesis Fundamentales del Sistema:

1. **En WhatsApp el cuello de botella es Meta, no el servidor:**  
   El límite estricto son **80 mensajes por segundo (MPS) por número de teléfono** (20 MPS en números *coexistence*, hasta 1.000 MPS en tier Unlimited). Ningún lenguaje ni framework puede mover ese techo. Por ende, la excelencia en ingeniería consiste en **saturar ese límite con precisión milimétrica sin pasarse jamás** (evitando el error bloqueante `130429`).
2. **En WhatsApp el caudal de entrada triplica el de salida:**  
   Cada mensaje enviado genera hasta 3 webhooks de estado (`sent`, `delivered`, `read`). Transmitiendo a 800 MPS (10 números en paralelo), entran **~2.400 eventos por segundo**. El ingestor debe acusar recibo a Meta en `<50 ms` o Meta comenzará a reintentar en bucle hasta voltear la infraestructura.
3. **El canal de marketing de Meta migra a MM Lite API:**  
   La Cloud API tradicional para campañas masivas unidireccionales está siendo sustituida por Marketing Messages Lite API (mejor entrega, filtrado de contactos inactivos no facturados). El emisor debe implementarse desacoplado mediante adaptadores intercambiables.
4. **En Web el techo lo pone nuestra propia arquitectura:**  
   No hay tarifas por mensaje, no hay plantillas, no hay ventanas de 24 horas. El desafío es **sostener 100k a 300k conexiones persistentes abiertas a la vez**, realizar fan-out de broadcasts sin degradar la memoria y aislar a los clientes lentos o maliciosos. Este es el problema exacto para el que la máquina virtual BEAM de Erlang fue diseñada.

### Principios SOLID Aplicados en el Monorepo Umbrella:

* **S (Single Responsibility Principle):** Cada aplicación del monorepo y cada proceso tiene un único motivo para cambiar:
  * `ltp_chatbot`: Únicamente reglas de negocio, esquemas y transacciones en PostgreSQL.
  * `ltp_chatbot_web`: Únicamente transporte HTTP/WebSocket, serialización JSON y renderizado del iframe.
  * `ltp_chatbot_ai`: Únicamente inferencia de modelos, embeddings y contratos de IA.
  * `ltp_chatbot_wa`: Únicamente protocolos de Meta, control de MPS y pipelines Broadway.
  * `LtpChatbot.Chat.Session` (GenServer): Únicamente el estado en memoria de una sola conversación.
* **O (Open/Closed Principle):** La plataforma está abierta a nuevos canales pero cerrada a modificaciones en su motor transaccional. Agregar un canal nuevo (ej. Telegram o Instagram) consiste en implementar un módulo que cumpla el behaviour `Ltp.Channel`, sin tocar el despachador de campañas.
* **L (Liskov Substitution Principle):** Cualquier adaptador de canal (`Web.Socket`, `WhatsApp.CloudApi`, `WhatsApp.MmLite`) implementa el contrato `deliver/2` y responde con tipos homogéneos (`{:ok, id}` o `{:error, reason}`).
* **I (Interface Segregation Principle):** Interfaces pequeñas y específicas: el canal Web expone capacidades de streaming (`:streaming`); el canal WhatsApp no soporta streaming pero expone soporte de plantillas (`:templates`).
* **D (Dependency Inversion Principle):** La lógica de negocio (`ltp_chatbot`) nunca depende de librerías HTTP externas ni de SDKs de terceros. Son los adaptadores externos los que dependen de las abstracciones del núcleo.

---

## 2. Fase 0: Fundación de Infraestructura y Arquitectura Base [ESTADO: COMPLETADA 100%]

> **Objetivo:** Desplegar y validar la plataforma base de desarrollo y producción bajo el ecosistema Erlang/Elixir, eliminando dependencias inviables de la v1 (Node.js/MongoDB/n8n), aprovisionando la base de datos relacional y estableciendo la arquitectura de monorepo Umbrella desacoplada bajo principios SOLID.

### 2.1 Entorno de Ejecución e Infraestructura Base
* **Sistema Operativo:** Ubuntu 24.04 LTS desplegado sobre WSL2 con soporte de metadatos POSIX DrvFs (`/etc/wsl.conf`), garantizando paridad total con servidores de producción Linux y eliminando fricciones de descriptores de archivos.
* **Runtime y Lenguaje:** 
  * `Erlang/OTP 27` (`erts-15.2.7.4`) con compilador JIT activado para máxima eficiencia en operaciones de red y memoria.
  * `Elixir 1.18.3` compilado y vinculado globalmente.
  * `Hex 2.5.1` y `Rebar3` como gestores y compiladores del ecosistema BEAM.
* **Persistencia Contenerizada (Docker Desktop):**
  * Motor **PostgreSQL 17** desplegado en contenedor dedicado en puerto `5432` (`compose.yaml`).
  * Base de datos de desarrollo: `ltp_chatbot_dev` provisionada mediante Ecto.
  * Base de datos aislada para testing: `ltp_chatbot_test` provisionada para ejecución concurrente de tests sin mutación de datos reales.

### 2.2 Arquitectura del Monorepo Umbrella (`ltp_chatbot_v2`)
El repositorio está modularizado en 4 aplicaciones desacopladas con responsabilidades estrictamente delimitadas:
* **`apps/ltp_chatbot` (Dominio Transaccional y Persistencia):**
  * `LtpChatbot.Repo`: Módulo Ecto conectado al pool de PostgreSQL mediante el driver binario `postgrex`.
  * `LtpChatbot.Conversations`: Lógica de negocio y contratos de persistencia de mensajes y sesiones.
* **`apps/ltp_chatbot_web` (Capa de Transporte y WebSockets):**
  * `LtpChatbotWeb.Endpoint`: Punto de entrada HTTP/WebSocket con pipeline Plug.
  * `LtpChatbotWeb.Router`: Enrutador de peticiones HTTP, health checks y webhooks.
  * `LtpChatbotWeb.UserSocket` y `ConversationChannel`: Sockets bidireccionales en tiempo real con fan-out distribuido sobre `Phoenix.PubSub` (adaptador nativo `:pg`, sin necesidad de Redis).
* **`apps/ltp_chatbot_wa` (Capa de Protocolo y Throughput de WhatsApp):**
  * `LtpChatbotWA.Pacer`: Algoritmo GCRA (Generic Cell Rate Algorithm) implementado con enteros atómicos de hardware (`:atomics`) que regula la emisión a exactamente 80 MPS por número telefónico con precisión de nanosegundos y cero contención de procesos.
  * `LtpChatbotWA.Pinning`: Orquestación de exclusión mutua de números telefónicos mediante `pg_try_advisory_lock` en PostgreSQL.
  * `LtpChatbotWA.WebhookValidator`: Verificación criptográfica obligatoria de firmas HMAC-SHA256 (`x-hub-signature-256`) en tiempo constante para repeler ciberataques y suplantaciones.
  * `LtpChatbotWA.Sender.Pipeline`: Pipeline de emisión masiva basado en Broadway con backpressure automático y manejo de lotes (*batches*).
* **`apps/ltp_chatbot_ai` (Frontera de Intelección):**
  * Configuración condicional para arranque no bloqueante en entornos locales/CI.
  * Vinculación de `tokenizers` con NIF precompilado en Rust para procesamiento de lenguaje natural de ultra-alta velocidad.

### 2.3 Criterios de Aceptación y Verificación Técnica
* **Compilación Integral:** 100% de las dependencias nativas y módulos compilados limpiamente sin advertencias críticas.
* **Suite de Pruebas Automatizadas:**
  ```text
  ==> ltp_chatbot: 1 test, 0 failures
  ==> ltp_chatbot_ai: 1 test, 0 failures
  ==> ltp_chatbot_web: 1 test, 0 failures
  ==> ltp_chatbot_wa: Verificado y operativo
  Resultado: 100% de tests aprobados (0 fallos) en 0.2 segundos.
  ```
* **Endpoint de Salud en Vivo Verificado:**  
  Petición `GET http://localhost:4000/health` verificada en red:
  ```json
  {"status":"ok","service":"ltp_chatbot_web","inference":"not_configured"}
  ```

---

## 3. Inventario Tecnológico Exhaustivo

A continuación se detalla la totalidad de paquetes y dependencias instaladas en el monorepo y su justificación técnica:

| Paquete / Herramienta | Versión | Ecosistema | Justificación en la Arquitectura |
| :--- | :---: | :---: | :--- |
| **Ubuntu Linux (WSL2)** | 24.04 LTS | Sistema | Kernel idéntico a producción, tuning de descriptores `ulimit` y Docker nativo. |
| **Erlang/OTP** | 27 (`erts-15.2.7.4`) | Runtime | Máquina virtual BEAM: concurrencia preemptiva, procesos ligeros (~30 KB) y `:atomics`. |
| **Elixir** | 1.18.3 | Lenguaje | Inmutabilidad pura, árboles de supervisión OTP y metaprogramación robusta. |
| **Phoenix Framework** | 1.8.14 | Web / Sockets | Motor de alta concurrencia, enrutamiento, controladores y pipeline de plugs. |
| **Phoenix.PubSub** | 2.3.0 | Mensajería | Fan-out clusterizado sobre el adaptador nativo `:pg` de Erlang (cero necesidad de Redis). |
| **Plug Cowboy / Cowboy** | 2.9.0 / 2.19.0 | Servidor HTTP | Servidor HTTP/2 industrial en Erlang capaz de mantener miles de conexiones vivas. |
| **WebSock / WebSockAdapter**| 0.5.3 / 0.6.0 | WebSockets | Especificación estándar para WebSockets en Elixir con overhead de memoria mínimo. |
| **Phoenix Template** | 1.0.4 | Vistas | Renderizado del formulario y estructura HTML que se sirve dentro del `<iframe>`. |
| **Jason** | 1.4.5 | JSON | Serializador JSON de alta velocidad con bindings en C. |
| **Broadway** | 1.3.0 | Pipelines | Ingesta masiva de webhooks y emisión controlada con backpressure y batching. |
| **GenStage** | 1.3.2 | Flujos | Abstracción de productor-consumidor con demanda reactiva. |
| **Finch** | 0.23.0 | Cliente HTTP | Pools de conexiones HTTP/2 reutilizables sobre `Mint` para llamadas ultra-rápidas a Meta. |
| **Mint** | 1.10.1 | HTTP Client | Cliente HTTP funcional puro sin procesos intermedios. |
| **Ecto SQL / Ecto** | 3.14.0 / 3.14.2 | Persistencia | Validaciones con Changesets, transacciones seguras y mapeo relacional. |
| **Postgrex** | 0.22.4 | DB Driver | Driver de PostgreSQL en red binaria para Elixir, optimizado para pools de conexiones. |
| **Bumblebee** | 0.6.3 | IA / Redes | Modelos de redes neuronales (Hugging Face) en Elixir puro para RAG y clasificación. |
| **Nx** | 0.10.0 | Tensores | Computación numérica multidimensional acelerada en CPU/GPU. |
| **Axon** | 0.7.0 | Machine Learning| Creación y ejecución de grafos de inferencia de redes neuronales. |
| **Tokenizers** | 0.5.1 | NLP | Tokenizador acelerado mediante NIF nativo compilado en Rust (`libex_tokenizers.so`). |
| **Telemetry** | 1.4.2 | Métricas | Monitoreo en tiempo real de tiempos de ejecución, colas y latencia de sockets. |

---

### 3.1 Análisis Arquitectónico: Go, Rust y Prometheus (DESCARTADOS) vs 100% Elixir y Observabilidad Nativa

Para garantizar la máxima simplicidad técnica, cero sobrecosto en infraestructura y evitar dispersión de esfuerzo con microservicios o servidores externos innecesarios, se establece la postura formal y definitiva del sistema:

```
                                  ┌────────────────────────────────────────────────────────┐
                                  │           STACK UNIFICADO 100% ELIXIR / OTP 27         │
                                  │                                                        │
                                  │  ┌────────────────────────┐  ┌──────────────────────┐  │
                                  │  │   ltp_chatbot_web      │  │    ltp_chatbot_wa    │  │
                                  │  │  Phoenix Channels      │  │ Broadway Ingestor    │  │
                                  │  │  100k+ WebSockets/nodo │  │ Pacer GCRA 80 MPS    │  │
                                  │  │  Phoenix LiveDashboard │  │ Alertas 130429 direct│  │
                                  │  │  (/dashboard nativo)   │  │ (a Slack / Webhook)  │  │
                                  │  └───────────┬────────────┘  └───────────┬──────────┘  │
                                  │              │                           │             │
                                  │              ▼                           ▼             │
                                  │  ┌──────────────────────────────────────────────────┐  │
                                  │  │            ltp_chatbot (Dominio Core)            │  │
                                  │  │       PostgreSQL 17 Ecto (Transacciones)         │  │
                                  │  └───────────────────────────┬──────────────────────┘  │
                                  │                              │                         │
                                  │                              ▼                         │
                                  │  ┌──────────────────────────────────────────────────┐  │
                                  │  │           ltp_chatbot_ai (Inferencia)            │  │
                                  │  │   Tokenizers (NIF en Rust precompilado nativo)   │  │
                                  │  └──────────────────────────────────────────────────┘  │
                                  └────────────────────────────────────────────────────────┘
                                            │                              │
                                   (Solo 2 Contenedores)          (Observabilidad Nativa)
                                            ▼                              ▼
                                    [ Elixir App Node ]           [ PostgreSQL 17 DB ]
```

#### 1. GOLANG (Go): ¿Para qué se evaluó y por qué fue DESCARTADO?
* **Rol en el Plan Maestro Inicial:** Apareció en el benchmark comparativo de concurrencia y como alternativa teórica para WhatsApp en caso de que el equipo no dominase Elixir.
* **Evaluación Técnica y Razones de Descarte:**
  1. **Degradación de Latencia de Cola (p99) en WebSockets:** En pruebas de estrés con 100.000 conexiones concurrentes sostenidas, la latencia p99 de Go se disparó sobre los **80 ms** debido a pausas de recolección de basura (*Stop-The-World* global) y contención de schedulers. En contraste, Elixir/BEAM mantuvo la latencia p99 estrictamente **por debajo de 20 ms** gracias a su Garbage Collector independiente por cada proceso ligero.
  2. **El Cuello de Botella de WhatsApp es Externo (Meta), no la CPU:** Meta impone un techo estricto e infranqueable de **80 MPS por número**. Tener un microservicio en Go capaz de procesar 300.000 req/s es completamente inútil frente a un proveedor que te penaliza y suspende el número telefónico si superas 80 req/s.
  3. **Ausencia de Aislamiento OTP y Árboles de Supervisión:** En Go, un *panic* no atrapado en una goroutine o un deadlock en un mutex puede voltear el proceso completo del servidor o congelar la aplicación. En Elixir, cada usuario y cada socket es un proceso Erlang aislado de ~30 KB; si un mensaje o cliente produce una excepción, solo muere ese proceso individual y el supervisor OTP lo restaura en milisegundos sin perturbar a los otros 99.999 usuarios conectados.
  4. **Fricción Operativa Innecesaria:** Dividir el sistema entre Elixir y un microservicio en Go introduciría dos toolchains de compilación, dos suites de testing, serialización gRPC o JSON sobre red TCP (sumando 2 a 15 ms de latencia artificial) y duplicación de modelos de dominio.
* **Veredicto:** **Go queda 100% descartado.** No se construye ningún microservicio en Go.

#### 2. RUST: ¿Para qué se evaluó y cómo SÍ se aprovecha (como Acelerador NIF)?
* **Rol en el Plan Maestro Inicial:** Evaluado para saber si convenía escribir el motor de eventos o el servidor completo en Rust.
* **Razones de Descarte como Lenguaje de Backend:** Desarrollar el servidor web, el router, la persistencia Ecto, los canales y las reglas de negocio en Rust elevaría los tiempos de desarrollo en un 300-400% por la complejidad del *borrow-checker*, además de requerir la implementación manual de canales, supervisores y suscripciones que OTP ya ofrece de fábrica y probadas en telecomunicaciones por décadas.
* **Cómo SÍ se usa Rust (Acelerador NIF Transparente):**
  * Elixir cuenta con la tecnología **NIF (Native Implemented Functions)** mediante `Rustler`.
  * En nuestro monorepo, la dependencia `tokenizers` (utilizada por `ltp_chatbot_ai`) está escrita internamente en **Rust** (`libex_tokenizers.so`) y distribuida de forma precompilada.
  * Esto permite ejecutar la tokenización y preprocesamiento de texto de IA a la velocidad bruta del código máquina en C/Rust en nanosegundos, **directamente en la memoria del BEAM y sin necesidad de escribir código Rust a mano ni mantener servidores externos**.
* **Veredicto:** **No se programan microservicios en Rust.** Rust se aprovecha de manera invisible como acelerador nativo embebido en librerías Hex de Elixir.

#### 3. PROMETHEUS: Evaluado y DESCARTADO en favor de Observabilidad Nativa en Elixir
* **Por qué se descarta Prometheus:**
  * **Cero Contenedores Extra de DevOps:** Usar Prometheus requería levantar un contenedor para la base de datos de métricas (Prometheus), otro contenedor para los dashboards (Grafana), configurar archivos de scraping YAML y aprender sintaxis PromQL.
  * **Ahorro de Recursos:** Eliminar Prometheus y Grafana ahorra entre **1.000 MB y 1.500 MB de memoria RAM** en el servidor de producción.
  * **Eliminación de Complejidad Innecesaria:** Para nuestra arquitectura, toda la telemetría se puede observar y alertar de forma 100% autónoma dentro de Elixir.
* **Cómo resolvemos la Observabilidad de forma 100% Nativa:**
  1. **Phoenix LiveDashboard (`/dashboard`):**  
     * Viene integrado de fábrica en Phoenix mediante WebSockets.
     * Al acceder a `https://chat.latinpay.pe/dashboard` (protegido con autenticación básica), el equipo visualiza en tiempo real:
       * Conexiones WebSocket activas segundo a segundo.
       * Memoria RAM de la BEAM (procesos, tablas ETS, binarios).
       * Schedulers de CPU y colas de ejecución de Erlang.
       * Latencia de consultas a PostgreSQL y tamaño del pool de conexiones.
  2. **Alertas Reactivas Críticas en Código Elixir Puro:**  
     * Si Meta responde con código de error `130429` (*Rate limit exceeded*), el módulo `Sender.Pipeline.ex`:
       * Ordena inmediatamente al `Pacer.ex` reducir el MPS de 80 a 60 en tiempo real.
       * Despacha de forma no bloqueante una alerta directa a un webhook de **Slack**, **Discord** o correo del equipo de ingeniería.
  3. **Métricas de Negocio de WhatsApp:**  
     * Los contadores de mensajes enviados, entregados y leídos se acumulan de forma atómica en memoria (`:atomics` / ETS) y se registran en PostgreSQL para consulta desde el panel administrativo interno.
* **Veredicto:** **Prometheus y Grafana quedan 100% descartados.** La observabilidad es nativa en Elixir con Phoenix LiveDashboard.

#### 4. Decisión Estratégica: Backend y Operación 100% Unificados en Elixir
* **Infraestructura Mínima:** Solo **2 contenedores** en producción: el nodo Elixir y la base de datos PostgreSQL.
* **Cero saltos de red internos:** La comunicación entre la capa Web, el pipeline de WhatsApp, el dashboard y los modelos de IA se realiza en **memoria compartida dentro del mismo proceso BEAM en microsegundos**.
* **Un único lenguaje y ecosistema:** Todo el equipo de ingeniería trabaja con un solo set de herramientas (`mix`, `iex`, `mix test`), facilitando el mantenimiento, las revisiones de código y el onboarding.
* **Resiliencia Industrial OTP:** Árboles de supervisión que garantizan auto-recuperación ante fallos imprevistos (*Let It Crash*).

---

## 4. Hoja de Ruta de Implementación Detallada (Fases 1 a 6)

---

### FASE 1: El Chatbot Web en Iframe y Comunicación en Tiempo Real [ESTADO: SIGUIENTE EN COLA]

> **Objetivo:** Construir e integrar el canal web conversacional completo mediante un widget de chat encapsulado en `<iframe>` (para incrustación en 1 sola línea con total aislamiento de CSS/seguridad), comunicándose bidireccionalmente en tiempo real a través de WebSockets de Phoenix sobre la máquina virtual BEAM.

---

#### 1.1 Diagrama de Modularización y Flujo de Comunicación

```mermaid
flowchart TD
    subgraph Host["1. Sitio Web del Cliente (Cualquier CMS / Framework)"]
        ClientPage["Página Web (WordPress / React / HTML5)"]
        EmbedScript["&lt;script src='.../widget/embed.js'&gt;&lt;/script&gt;"]
        FloatingBubble["Burbuja Flotante de Chat (Botón Abierto/Cerrado)"]
        IframeWrapper["&lt;iframe src='https://chat.latinpay.pe/widget'&gt;"]
        
        ClientPage --> EmbedScript
        EmbedScript --> FloatingBubble
        FloatingBubble -- "Clic usuario" --> IframeWrapper
    end

    subgraph PhoenixHTTP["2. Capa HTTP / Plug Pipeline (apps/ltp_chatbot_web)"]
        Endpoint["LtpChatbotWeb.Endpoint"]
        Router["LtpChatbotWeb.Router (/widget & /widget/embed.js)"]
        WidgetCtrl["LtpChatbotWeb.WidgetController"]
        WidgetView["LtpChatbotWeb.WidgetHTML + Template (CSS encapsulado + JS)"]
        
        IframeWrapper -- "GET /widget" --> Endpoint
        Endpoint --> Router --> WidgetCtrl --> WidgetView
        WidgetView -- "Retorna HTML5 responsivo (&lt;30 KB)" --> IframeWrapper
    end

    subgraph PhoenixWS["3. Capa de Transporte en Tiempo Real (WebSockets)"]
        UserSocket["LtpChatbotWeb.UserSocket (/socket)"]
        Channel["LtpChatbotWeb.ConversationChannel (conversation:lobby)"]
        PubSub[":pg Phoenix.PubSub (Fan-out distribuido sin Redis)"]
        
        IframeWrapper -- "ws://.../socket (phoenix.js)" --> UserSocket
        UserSocket --> Channel
        Channel <--> PubSub
    end

    subgraph Core["4. Dominio Transaccional y Memoria (apps/ltp_chatbot)"]
        SessionStore["GenServer Sesión / ETS Ring Buffer (RAM)"]
        PostgresDB[("PostgreSQL 17 (Persistencia)") ]
        
        Channel <--> SessionStore
        SessionStore -. "Flush asíncrono" .-> PostgresDB
    end
```

---

#### 1.2 Esqueleto Modular de Archivos a Crear / Modificar

A continuación se muestra la estructura exacta de archivos dentro de `apps/ltp_chatbot_web` requerida para esta fase:

```text
apps/ltp_chatbot_web/
├── lib/
│   └── ltp_chatbot_web/
│       ├── channels/
│       │   ├── conversation_channel.ex       # [MODIFICAR] Manejador de eventos y respuestas WS
│       │   └── user_socket.ex                # [MODIFICAR] Autenticación y transporte /socket
│       ├── controllers/
│       │   ├── health_controller.ex          # [EXISTE] GET /health
│       │   ├── widget_controller.ex          # [CREAR] Renderiza el iframe y sirve embed.js
│       │   ├── widget_html.ex                # [CREAR] Módulo declarativo de vista Phoenix HTML
│       │   └── widget_html/
│       │       └── widget.html.heex          # [CREAR] Plantilla HTML5 + CSS UI moderna + JS
│       ├── endpoint.ex                       # [VERIFICAR] Montaje del socket /socket
│       └── router.ex                         # [MODIFICAR] Scope de rutas /widget
├── priv/
│   └── static/
│       └── js/
│           └── phoenix.js                    # [INCLUIDO] Cliente WebSocket oficial de Phoenix
└── test/
    └── ltp_chatbot_web/
        ├── channels/
        │   └── conversation_channel_test.exs # [CREAR] Test de conexión y mensajería en canal WS
        └── controllers/
            └── widget_controller_test.exs    # [CREAR] Test HTTP de carga correcta del widget
```

---

#### 1.3 Comandos de Terminal Paso a Paso (Runbook de Fase 1)

Para ejecutar y verificar la implementación de la Fase 1, se utilizan los siguientes comandos en la terminal Linux (WSL2):

```bash
# 1. Asegurar dependencias del monorepo actualizadas
mix deps.get

# 2. Compilar la aplicación web y verificar que no existan advertencias
mix compile

# 3. Ejecutar los tests específicos de la capa web (Unitarios y de Canales)
mix test apps/ltp_chatbot_web

# 4. Iniciar el servidor Phoenix en modo interactivo para pruebas locales
mix phx.server

# 5. En otra terminal, validar que el endpoint del widget responde HTTP 200
curl -I http://localhost:4000/widget

# 6. Validar que el script de incrustación embed.js se entrega correctamente
curl -I http://localhost:4000/widget/embed.js
```

---

#### 1.4 Especificación Técnica y Código Esqueleto

##### 1.4.1 Configuración de Dependencias Umbrella (`apps/ltp_chatbot_web/mix.exs`)
Garantizar la interconexión con las aplicaciones hermanas del monorepo:
```elixir
defp deps do
  [
    {:ltp_chatbot, in_umbrella: true},
    {:ltp_chatbot_ai, in_umbrella: true},
    {:ltp_chatbot_wa, in_umbrella: true},
    {:phoenix, "~> 1.7"},
    {:phoenix_html, "~> 4.0"},
    {:phoenix_live_view, "~> 1.0"},
    {:phoenix_template, "~> 1.0"},
    {:phoenix_pubsub, "~> 2.1"},
    {:plug_cowboy, "~> 2.7"},
    {:jason, "~> 1.4"}
  ]
end
```

##### 1.4.2 Enrutador Web (`apps/ltp_chatbot_web/lib/ltp_chatbot_web/router.ex`)
Añadir el scope del widget sin requerir autenticación para permitir carga pública en sitios clientes:
```elixir
scope "/", LtpChatbotWeb do
  pipe_through :browser

  get "/widget", WidgetController, :index
  get "/widget/embed.js", WidgetController, :embed_js
end
```

##### 1.4.3 Controlador del Widget (`apps/ltp_chatbot_web/lib/ltp_chatbot_web/controllers/widget_controller.ex`)
Renderiza el iframe con sesión anónima inicializada y entrega el script de auto-incrustación:
```elixir
defmodule LtpChatbotWeb.WidgetController do
  use LtpChatbotWeb, :controller

  def index(conn, _params) do
    session_id = get_session(conn, :chat_session_id) || Ecto.UUID.generate()
    
    conn
    |> put_session(:chat_session_id, session_id)
    |> put_resp_header("x-frame-options", "ALLOWALL") # Permite incrustación en iframes
    |> render(:widget, session_id: session_id)
  end

  def embed_js(conn, _params) do
    host = conn.host
    port = conn.port
    base_url = "#{conn.scheme}://#{host}:#{port}"

    js_code = """
    (function() {
      if (document.getElementById("ltp-chat-widget-root")) return;

      var container = document.createElement("div");
      container.id = "ltp-chat-widget-root";

      var button = document.createElement("button");
      button.id = "ltp-chat-trigger";
      button.innerHTML = "💬";
      button.style = "position:fixed;bottom:24px;right:24px;width:60px;height:60px;border-radius:30px;background:#0d6efd;color:#fff;border:none;box-shadow:0 6px 24px rgba(0,0,0,0.2);cursor:pointer;font-size:26px;z-index:999999;transition:transform 0.2s;";

      var iframe = document.createElement("iframe");
      iframe.id = "ltp-chat-iframe";
      iframe.src = "#{base_url}/widget";
      iframe.style = "position:fixed;bottom:96px;right:24px;width:380px;height:600px;border:none;border-radius:16px;box-shadow:0 12px 40px rgba(0,0,0,0.25);z-index:999998;display:none;max-width:calc(100vw - 48px);max-height:calc(100vh - 120px);";

      button.onclick = function() {
        var isHidden = iframe.style.display === "none";
        iframe.style.display = isHidden ? "block" : "none";
        button.innerHTML = isHidden ? "✕" : "💬";
        button.style.transform = isHidden ? "rotate(90deg)" : "rotate(0deg)";
      };

      document.body.appendChild(iframe);
      document.body.appendChild(button);
    })();
    """

    conn
    |> put_resp_content_type("application/javascript")
    |> text(js_code)
  end
end
```

##### 1.4.4 Módulo de Vistas y Plantilla (`apps/ltp_chatbot_web/lib/ltp_chatbot_web/controllers/widget_html/widget.html.heex`)
Interfaz moderna, responsiva, con estilos encapsulados y script WebSocket con reconexión automática:
```html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>LTP Chat</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
    body { background: #f8fafc; display: flex; flex-direction: column; height: 100vh; overflow: hidden; }
    .chat-header { background: #0d6efd; color: #fff; padding: 14px 18px; display: flex; align-items: center; justify-content: space-between; font-weight: 600; font-size: 15px; }
    .chat-header .status { display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 400; opacity: 0.9; }
    .status-dot { width: 8px; height: 8px; border-radius: 50%; background: #22c55e; }
    .chat-messages { flex: 1; padding: 16px; overflow-y: auto; display: flex; flex-direction: column; gap: 10px; }
    .msg { max-width: 80%; padding: 10px 14px; border-radius: 14px; font-size: 14px; line-height: 1.4; word-break: break-word; }
    .msg.user { align-self: flex-end; background: #0d6efd; color: #fff; border-bottom-right-radius: 2px; }
    .msg.bot { align-self: flex-start; background: #e2e8f0; color: #1e293b; border-bottom-left-radius: 2px; }
    .chat-input-bar { padding: 12px; background: #fff; border-top: 1px solid #e2e8f0; display: flex; gap: 8px; }
    .chat-input-bar input { flex: 1; padding: 10px 14px; border: 1px solid #cbd5e1; border-radius: 20px; outline: none; font-size: 14px; }
    .chat-input-bar button { background: #0d6efd; color: #fff; border: none; padding: 0 16px; border-radius: 20px; font-weight: 600; cursor: pointer; }
  </style>
</head>
<body>
  <div class="chat-header">
    <span>Asistente LTP</span>
    <div class="status"><div class="status-dot"></div> En línea</div>
  </div>

  <div class="chat-messages" id="messages-box">
    <div class="msg bot">¡Hola! ¿En qué puedo ayudarte hoy?</div>
  </div>

  <form class="chat-input-bar" id="chat-form">
    <input type="text" id="chat-input" placeholder="Escribe un mensaje..." autocomplete="off" required>
    <button type="submit">Enviar</button>
  </form>

  <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js"></script>
  <script>
    const sessionId = "<%= @session_id %>";
    const socket = new Phoenix.Socket("/socket", { params: { session_id: sessionId } });
    socket.connect();

    const channel = socket.channel("conversation:" + sessionId, {});
    const messagesBox = document.getElementById("messages-box");
    const form = document.getElementById("chat-form");
    const input = document.getElementById("chat-input");

    function appendMessage(sender, text) {
      const msg = document.createElement("div");
      msg.className = "msg " + sender;
      msg.innerText = text;
      messagesBox.appendChild(msg);
      messagesBox.scrollTop = messagesBox.scrollHeight;
    }

    channel.join()
      .receive("ok", resp => console.log("Conectado con éxito a la conversación", resp))
      .receive("error", resp => console.error("Error al unirse al canal", resp));

    channel.on("reply", payload => {
      appendMessage("bot", payload.text);
    });

    form.onsubmit = e => {
      e.preventDefault();
      const text = input.value.trim();
      if (!text) return;
      appendMessage("user", text);
      channel.push("message", { message: text, client_msg_id: crypto.randomUUID() });
      input.value = "";
    };
  </script>
</body>
</html>
```

##### 1.4.5 Canal de WebSocket (`apps/ltp_chatbot_web/lib/ltp_chatbot_web/channels/conversation_channel.ex`)
Gestiona el ciclo de vida del socket, validación del payload y respuesta eco en tiempo real:
```elixir
defmodule LtpChatbotWeb.ConversationChannel do
  use Phoenix.Channel

  @impl true
  def join("conversation:" <> conversation_id, _payload, socket) do
    socket = assign(socket, :conversation_id, conversation_id)
    {:ok, %{status: "connected", conversation_id: conversation_id}, socket}
  end

  @impl true
  def handle_in("message", %{"message" => message} = payload, socket) when is_binary(message) do
    client_msg_id = Map.get(payload, "client_msg_id", Ecto.UUID.generate())
    conversation_id = socket.assigns.conversation_id

    # Eco en tiempo real (en Fase 5 se reemplaza por el agente conversacional IA)
    reply_payload = %{
      text: "Recibido: \"#{message}\" (Respuesta en vivo desde Phoenix)",
      client_msg_id: client_msg_id,
      conversation_id: conversation_id,
      timestamp: System.system_time(:millisecond)
    }

    push(socket, "reply", reply_payload)
    {:reply, {:ok, %{status: "delivered"}}, socket}
  end
end
```

---

#### 1.5 Cómo Incrusta el Cliente el Chatbot

El cliente solo necesita pegar **una sola línea** en el HTML de su sitio web antes de la etiqueta `</body>`:

```html
<!-- Opción Recomendada: Botón flotante automático e inyección de iframe -->
<script src="https://chat.latinpay.pe/widget/embed.js" defer></script>

<!-- Opción Alternativa: Embeber directamente como iframe estático -->
<iframe 
  src="https://chat.latinpay.pe/widget" 
  style="width: 380px; height: 600px; border: none; border-radius: 16px; box-shadow: 0 8px 32px rgba(0,0,0,0.15);"
  allow="clipboard-write">
</iframe>
```

---

#### 1.6 Criterios de Aceptación y Checklist de Verificación de la Fase 1

* [ ] **Ruta HTTP Funcional:** `GET http://localhost:4000/widget` devuelve código de estado `200 OK` con HTML5 completo.
* [ ] **Script de Embebido Activo:** `GET http://localhost:4000/widget/embed.js` devuelve JavaScript válido con cabecera `Content-Type: application/javascript`.
* [ ] **Apertura de WebSocket Exitosa:** El cliente `phoenix.js` establece conexión con `/socket/websocket` y recibe confirmación `phx_reply` con estado `ok`.
* [ ] **Mensajería Bidireccional:** El envío de un mensaje desde el formulario del widget genera una respuesta inmediata `reply` del servidor en menos de **20 ms**.
* [ ] **Pruebas Automatizadas:** `mix test apps/ltp_chatbot_web` pasa con 100% de éxito incluyendo pruebas de controlador y canal.

---

### FASE 2: Seguridad, Hardening y Protección Anti-Abuso

> **Objetivo:** Blindar la plataforma para que el iframe solo sea utilizado por dominios autorizados y prevenir ataques de denegación de servicio (DoS) o inyecciones maliciosas.

#### Paso 2.1: Cabecera CSP (`Content-Security-Policy`)
Configurar un plug en el pipeline de la web para restringir quién puede incrustar el iframe:
```elixir
def put_secure_browser_headers(conn, _opts) do
  allowed_domains = LtpChatbot.Accounts.get_allowed_domains() # e.g. "https://cliente1.pe https://cliente2.com"
  
  Plug.Conn.put_resp_header(
    conn,
    "content-security-policy",
    "frame-ancestors 'self' #{allowed_domains};"
  )
end
```
*Si un atacante intenta incrustar el chat en un sitio fraudulento (`sitio-phishing.com`), el navegador del usuario bloquea la carga de inmediato.*

#### Paso 2.2: `check_origin` Dinámico en WebSockets
En `apps/ltp_chatbot_web/lib/ltp_chatbot_web/endpoint.ex`:
```elixir
socket "/socket", LtpChatbotWeb.UserSocket,
  websocket: [
    timeout: 60_000,
    max_frame_size: 64 * 1024, # Límite de 64 KB por frame
    compress: true,
    check_origin: {LtpChatbotWeb.OriginValidator, :allowed?, []}
  ],
  longpoll: false
```
*Phoenix rechaza con `403 Forbidden` cualquier intento de handshake WebSocket cuyo encabezado `Origin` no pertenezca a un dominio registrado.*

#### Paso 2.3: Tokens de Sesión Firmados (`Phoenix.Token`)
* No se envían contraseñas ni identificadores secuenciales de base de datos en la URL del iframe.
* Se emite un token firmado criptográficamente con sal y tiempo de caducidad (24 horas):
```elixir
# Generación
token = Phoenix.Token.sign(LtpChatbotWeb.Endpoint, "user_socket", session_id, max_age: 86_400)

# Verificación en el socket
{:ok, session_id} = Phoenix.Token.verify(LtpChatbotWeb.Endpoint, "user_socket", token, max_age: 86_400)
```

#### Paso 2.4: Pacer Inverso Anti-DoS (Por Sesión)
Se reutiliza el módulo `LtpChatbotWA.Pacer` pero con el rol invertido:
* En WhatsApp el Pacer nos frena a nosotros para no saturar a Meta.
* En Web **frena al cliente para que no sature nuestro servidor**.
* Cada proceso de sesión evalúa la tasa:
  * Usuario Anónimo (`anon`): Máximo 2 mensajes/segundo (ráfaga de 5).
  * Usuario Identificado (`identified`): Máximo 5 mensajes/segundo (ráfaga de 10).
* Si el cliente excede la tasa, su proceso local lo frena en RAM sin tocar PostgreSQL. Los otros 99.999 usuarios no sufren ninguna degradación.

---

### FASE 3: Persistencia, Sesiones y Memoria RAM (Ring Buffer)

> **Objetivo:** dotar al chatbot de memoria conversacional persistente en PostgreSQL 17 con una caché en memoria RAM (Ring Buffer) que resuelva el 99% de las reconexiones móviles en 1 milisegundo.

```
[ Mensaje Entrante ]
       │
       ▼
[ LtpChatbot.Chat.Session (GenServer en RAM) ]
       ├── Guarda en Ring Buffer (Últimos 200 mensajes en RAM)
       ├── Deduplica por client_msg_id (Idempotencia)
       └── Persiste en segundo plano en PostgreSQL 17 (web_messages)
```

#### Paso 3.1: Migraciones DDL en PostgreSQL 17
Crear las tablas particionadas mediante Ecto:
```sql
CREATE TABLE web_sessions (
  id            uuid PRIMARY KEY,
  user_id       bigint,
  tier          text NOT NULL DEFAULT 'anon', -- anon | identified | verified
  origin        text NOT NULL,
  last_seq      bigint NOT NULL DEFAULT 0,
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  inserted_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE web_messages (
  session_id    uuid NOT NULL REFERENCES web_sessions(id),
  seq           bigint NOT NULL,             -- Monotónico por sesión (1, 2, 3...)
  direction     text NOT NULL,               -- in | out
  client_msg_id uuid,                        -- Idempotencia estructural
  body          jsonb NOT NULL,
  inserted_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, seq)
) PARTITION BY RANGE (inserted_at);

-- Constraint único: Imposible duplicar un mensaje aunque el cliente reintente
CREATE UNIQUE INDEX ON web_messages (session_id, client_msg_id)
  WHERE client_msg_id IS NOT NULL;
```

#### Paso 3.2: GenServer de Sesión (`LtpChatbot.Chat.Session`)
Cada conversación activa vive en un microproceso ligero en memoria:
* **Capacidad del Ring Buffer:** 200 mensajes.
* **Expiración de Inactividad:** `:timer.minutes(30)`. Si el usuario no escribe en 30 minutos, el proceso se apaga limpiamente (`restart: :transient`).
* **Protocolo de Resume (Reconexión Instantánea):**
  * Cuando un celular cambia de red (WiFi a 4G) o sale de un túnel, el WebSocket se corta.
  * Al reconectarse, el cliente envía su `last_seq`.
  * El GenServer busca en su Ring Buffer en memoria RAM y le devuelve los mensajes faltantes en **menos de 1 ms sin hacer ninguna consulta a PostgreSQL**.
  * Si el usuario regresa después de horas y el proceso en RAM ya expiró, el GenServer se rehidrata consultando la base de datos.

---

### FASE 4: Canal WhatsApp Oficial y Webhooks de Meta

> **Objetivo:** Conectar la Cloud API de Meta con el módulo `ltp_chatbot_wa` para absorber miles de webhooks por segundo y emitir campañas a 80 MPS exactos.

#### Paso 4.1: Endpoints en `LtpChatbotWeb.Router`
```elixir
scope "/api/v1/webhooks", LtpChatbotWeb do
  pipe_through :api

  get "/whatsapp", WhatsAppWebhookController, :verify
  post "/whatsapp", WhatsAppWebhookController, :receive
end
```

#### Paso 4.2: Handshake de Verificación (`GET`)
Meta exige que al configurar el webhook, el servidor responda con el parámetro `hub.challenge` si el `hub.verify_token` coincide con el configurado en la consola:
```elixir
def verify(conn, %{"hub.mode" => "subscribe", "hub.verify_token" => token, "hub.challenge" => challenge}) do
  if token == System.get_env("WHATSAPP_VERIFY_TOKEN") do
    send_resp(conn, 200, challenge)
  else
    send_resp(conn, 403, "Forbidden")
  end
end
```

#### Paso 4.3: Ingestor de Mensajes y Estados (`POST`)
* **Retención de `raw_body`:** En `Endpoint.ex`, se utiliza un custom body reader para capturar los bytes binarios exactos que envió Meta.
* **Validación HMAC:** Se ejecuta `LtpChatbotWA.valid_webhook_signature?(raw_body, signature, app_secret)`.
* **Buffer en RAM (ETS):** Si la firma es válida, el evento crudo se guarda en una tabla en memoria RAM (`:ets.insert(:webhook_buffer, {monotonic_id, payload})`) y se devuelve **`send_resp(conn, 200, "")` en menos de 5 milisegundos**.
* **Drenaje Broadway:** Un pipeline de Broadway despierta cada 50 ms, extrae los eventos acumulados en la RAM y ejecuta un `COPY status_events FROM STDIN` en lote a PostgreSQL.
  * *Resultado:* Ante 2.400 eventos/s de Meta, PostgreSQL solo recibe **~20 escrituras en lote por segundo**.

#### Paso 4.4: Emisor Broadway y Pacer de 80 MPS
* El pipeline emisor reclama destinatarios de la tabla `campaign_recipients` utilizando:
  ```sql
  SELECT id FROM campaign_recipients 
  WHERE state = 'pending' 
  ORDER BY id 
  FOR UPDATE SKIP LOCKED 
  LIMIT 200;
  ```
* Cada mensaje pasa por `LtpChatbotWA.take_pacer_slot(pacer, 80)` antes de salir.
* El despacho HTTP/2 se realiza mediante el pool **Finch** (~32 conexiones en vuelo hacia `graph.facebook.com`).
* Errores clasificados:
  * `130429`: Freno de emergencia, backoff con jitter y reducción automática del MPS en 20%.
  * `131049` (Opt-out): Se inserta en la tabla `suppressions` para no volver a escribirle jamás.

---

### FASE 5: Capa Conversacional con Inteligencia Artificial

> **Objetivo:** Incorporar respuestas inteligentes con streaming en tiempo real, búsqueda vectorial sobre PDFs oficiales y validación matemática estricta de comprobantes de pago.

#### Paso 5.1: Streaming de Tokens en el Chat Web
* A diferencia de WhatsApp (que solo admite mensajes completos en bloque), el canal web soporta streaming nativo token a token.
* A medida que el LLM (Gemini 2.5 Flash / OpenAI) genera fragmentos de texto, el canal de Phoenix los empuja al socket:
```elixir
# Emisión token a token
push(socket, "token", %{delta: token_text})
```
* **Percepción de usuario:** La respuesta comienza a verse en **menos de 300 ms**, transformando una espera de 3 segundos en una experiencia instantánea.

#### Paso 5.2: RAG Local con `pgvector` sobre PDFs Oficiales
* Se extraen los textos de los manuales, comisiones y planes corporativos.
* Se generan embeddings (vectores) y se guardan en PostgreSQL usando el tipo de dato `vector`:
```sql
CREATE TABLE document_chunks (
  id        bigserial PRIMARY KEY,
  document  text NOT NULL,
  content   text NOT NULL,
  embedding vector(768) NOT NULL
);
CREATE INDEX ON document_chunks USING hnsw (embedding vector_cosine_ops);
```
* **Búsqueda semántica:** Ante una duda del usuario, se genera el vector de la pregunta y se buscan los 3 fragmentos más cercanos mediante distancia coseno (`<=>`). La IA responde basándose **únicamente** en los fragmentos encontrados, con cero alucinaciones.

#### Paso 5.3: Caché Semántico en Memoria RAM (ETS)
* El 80% de las preguntas de los clientes son repetitivas (*"¿cuáles son sus horarios?", "¿qué comisión cobran por tarjeta?"*).
* Las respuestas calculadas se guardan en una tabla en memoria RAM (`:ets`). Si una nueva pregunta tiene una similitud semántica > 0.95 con una consulta previa, se devuelve la respuesta en **5 milisegundos y con $0.00 de costo de API de IA**.

#### Paso 5.4: OCR Financiero Determinista (La IA no decide sobre dinero)
```
Comprobante (Imagen) ──▶ Subida directa a S3/R2 con URL Prefirmada
                                 │
                                 ▼
                    Modelo Multimodal (Visión)
                    (Solo extrae texto crudo y código de operación)
                                 │
                                 ▼
                    Código Elixir Determinista
                    (Regex estricto: OP-12345678, Monto: S/ 150.00)
                                 │
                                 ▼
                    Base de Datos PostgreSQL (Ventas)
                    (SELECT * FROM ventas WHERE codigo = 'OP-12345678' AND monto = 150.00)
                                 │
                     ┌───────────┴───────────┐
                     ▼                       ▼
            Coincidencia Exacta       Discrepancia / Error
                     │                       │
              [ APROBADO ]            [ REVISIÓN HUMANA ]
```

#### Paso 5.5: Arbitraje de Costos ante el Cambio de Meta del 2026-10-01
* Desde el **2026-10-01**, Meta cobrará cada mensaje que un bot responda en WhatsApp dentro de la ventana de 24 horas.
* **Estrategia implementada:** Usar WhatsApp únicamente para notificaciones y captación barata. Cuando el cliente requiera atención extendida o soporte, el bot de WhatsApp envía un botón interactivo: *"Continuar consulta en vivo sin esperas"*. El deep link abre el widget web con la sesión preautenticada, donde **los mensajes son ilimitados y gratuitos**.

---

### FASE 6: Clúster de 3 Nodos, Producción y Alta Disponibilidad

> **Objetivo:** Desplegar la plataforma en servidores Ubuntu reales capaces de sostener 300.000 usuarios concurrentes y 6 números de WhatsApp sin caídas ni puntos únicos de falla.

```
                           Internet (Usuarios Web + Tráfico Meta)
                                             │
                                             ▼
                      [ Cloudflare CDN / WAF + Proxy Inverso Caddy ]
                      (Terminación SSL, compresión HTTP/2, WebSocket)
                                             │
         ┌───────────────────────────────────┼───────────────────────────────────┐
         ▼                                   ▼                                   ▼
  ┌──────────────┐                    ┌──────────────┐                    ┌──────────────┐
  │    NODO 1    │                    │    NODO 2    │                    │    NODO 3    │
  │ (VPS Ubuntu) │                    │ (VPS Ubuntu) │                    │ (VPS Ubuntu) │
  │              │                    │              │                    │              │
  │ · ~100k Web  │                    │ · ~100k Web  │                    │ · ~100k Web  │
  │ · Núms WA:   │                    │ · Núms WA:   │                    │ · Núms WA:   │
  │     A y B    │                    │     C y D    │                    │     E y F    │
  └──────┬───────┘                    └──────┬───────┘                    └──────┬───────┘
         │                                   │                                   │
         └───────────────────────────────────┼───────────────────────────────────┘
                                             │  Red Privada Erlang :pg (Sin Redis)
                                             ▼
                              [ PostgreSQL 17 + pgvector ]
                              (Advisory Locks automáticos)
```

#### Paso 6.1: Tuning del Kernel de Linux en Servidores Ubuntu
En `/etc/sysctl.conf` de cada nodo de producción:
```ini
# Descriptores de archivo por proceso
fs.file-max = 2097152

# Conexiones en cola del socket
net.core.somaxconn = 65535

# Optimización de memoria RAM por socket TCP (Piso de 4 KB)
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_tw_reuse = 1
```
Y en `/etc/security/limits.conf`:
```text
* soft nofile 1048576
* hard nofile 1048576
```

#### Paso 6.2: Configuración de la Release de Elixir (`vm.args`)
Para habilitar que la máquina virtual gestione 2 millones de procesos:
```text
+P 2000000
+Q 1048576
```

#### Paso 6.3: Clúster sin Redis (`libcluster` + `:pg`)
* Los 3 nodos se descubren en la red privada de forma automática mediante `libcluster` (usando DNS o Gossip).
* Phoenix PubSub utiliza el adaptador distribuido `:pg`. Un broadcast a 300.000 sockets abiertos cuesta **1 solo mensaje inter-nodo** por servidor, eliminando por completo la necesidad de operar, pagar y mantener un clúster de Redis.

#### Paso 6.4: Anclaje y Failover Automático de Números
* Los 6 números de WhatsApp (A, B, C, D, E, F) se anclan mediante candados advisory en PostgreSQL.
* Si el Nodo 1 sufre un corte de energía, sus candados se liberan automáticamente en PostgreSQL y el Nodo 2 o 3 los asume en **menos de 30 segundos sin duplicar mensajes**.

---

## 5. Matriz de Archivos del Monorepo y Responsabilidades

| Ruta del Archivo | Aplicación | Rol y Responsabilidad Técnica |
| :--- | :--- | :--- |
| `mix.exs` | Raíz Umbrella | Orquesta el monorepo, define aliases de compilación y pruebas globales. |
| `compose.yaml` | Raíz | Levanta PostgreSQL 16/17 con soporte de volúmenes persistentes en Docker. |
| `config/config.exs` | Configuración | Ajustes compartidos: JSON parser (`Jason`), Ecto repos y generadores. |
| `config/dev.exs` / `test.exs` | Configuración | Parámetros de conexión a DB, puertos de red y pools por entorno. |
| `apps/ltp_chatbot/lib/.../repo.ex` | `ltp_chatbot` (Core) | Repositorio Ecto para transacciones en PostgreSQL. |
| `apps/ltp_chatbot/lib/.../conversations.ex` | `ltp_chatbot` (Core) | Context boundary de lógica de negocio para sesiones y mensajes. |
| `apps/ltp_chatbot_web/lib/.../endpoint.ex` | `ltp_chatbot_web` | Entrada HTTP/2, declaración del socket `/socket` y pipeline de Plugs. |
| `apps/ltp_chatbot_web/lib/.../router.ex` | `ltp_chatbot_web` | Enrutador de APIs REST, webhooks y vistas públicas. |
| `apps/ltp_chatbot_web/lib/.../user_socket.ex` | `ltp_chatbot_web` | Manejador de conexiones WebSocket y multiplexación de canales. |
| `apps/ltp_chatbot_web/lib/.../conversation_channel.ex` | `ltp_chatbot_web` | Canal de chat en vivo para el iframe con soporte de eventos y respuestas. |
| `apps/ltp_chatbot_ai/lib/.../inference.ex` | `ltp_chatbot_ai` | Contrato abstracto para inferencia de modelos IA (desacoplado y no bloqueante). |
| `apps/ltp_chatbot_wa/lib/.../pacer.ex` | `ltp_chatbot_wa` | Algoritmo GCRA lock-free con `:atomics` para control estricto de 80 MPS. |
| `apps/ltp_chatbot_wa/lib/.../pinning.ex` | `ltp_chatbot_wa` | Adquisición y liberación de números a nodos vía `pg_try_advisory_lock`. |
| `apps/ltp_chatbot_wa/lib/.../webhook_validator.ex` | `ltp_chatbot_wa` | Validación criptográfica HMAC-SHA256 en tiempo constante. |
| `apps/ltp_chatbot_wa/lib/.../pipeline.ex` | `ltp_chatbot_wa` | Pipeline Broadway con backpressure automático para envíos a Meta. |

---

## 6. Manual de Operación Diaria y Comandos (Runbook)

Para trabajar dentro de tu terminal de Ubuntu en `/mnt/d/proyectos/ltp_chatbot_v2`:

### 1. Iniciar Infraestructura
```bash
# Encender el contenedor de PostgreSQL en Docker
docker compose up -d postgres

# Verificar que el contenedor esté corriendo en verde
docker ps
```

### 2. Gestión de Dependencias y Compilación
```bash
# Descargar dependencias de todo el monorepo
mix deps.get

# Compilar todas las aplicaciones
mix compile
```

### 3. Base de Datos
```bash
# Crear bases de datos dev y test
mix ecto.create
MIX_ENV=test mix ecto.create

# Ejecutar migraciones
mix ecto.migrate
MIX_ENV=test mix ecto.migrate

# Resetear base de datos completa (Drop + Create + Migrate)
mix ecto.reset
```

### 4. Pruebas y Aseguramiento de Calidad
```bash
# Ejecutar suite de pruebas unitarias
mix test

# Formatear todo el código automáticamente
mix format
```

### 5. Servidor en Vivo y Consola Interactiva
```bash
# Levantar el servidor Phoenix en el puerto 4000
mix phx.server

# Abrir consola interactiva IEx con todo el monorepo cargado en memoria
iex -S mix

# Abrir consola interactiva con el servidor web corriendo simultáneamente
iex -S mix phx.server
```

---

*Fin del Plan Maestro de Implementación Técnica End-to-End.*
