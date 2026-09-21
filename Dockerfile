FROM hexpm/elixir:1.17.3-erlang-27.1-debian-bookworm-20240910-slim AS build

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs .formatter.exs ./
COPY config ./config
COPY apps ./apps

RUN mix deps.get --only prod
RUN mix compile
RUN mix release

FROM debian:bookworm-slim AS release
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
COPY --from=build /app/_build/prod/rel/ltp_chatbot ./
CMD ["/app/bin/ltp_chatbot", "start"]
