# LTP Chatbot

Monorepo umbrella para el backend del chatbot. La base está separada en dominio, transporte Phoenix e integración de inferencia con Bumblebee.

## Requisitos

- Elixir y Erlang compatibles con Phoenix 1.7.
- Docker y Docker Compose.

## Inicio rápido

```bash
cp .env.example .env
docker compose up -d postgres
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

El servicio queda disponible en `http://localhost:4000`.

## Comandos útiles

```bash
mix format
mix test
mix ecto.reset
```

Bumblebee está encapsulado en `apps/ltp_chatbot_ai` y todavía no descarga ni carga modelos. La inferencia se activará en una iteración posterior mediante configuración explícita.
