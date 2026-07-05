FROM debian:trixie-slim

ENV MISE_VERSION=v2026.7.0
ENV MISE_TRUSTED_CONFIG_PATHS="/app"

ENV MIX_ENV=test \
    MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    DIAGNOSTIC=1

ENV PATH="/root/.local/bin:/root/.local/share/mise/shims:${PATH}"

RUN apt update -y && \
    apt install -y curl git build-essential libssl-dev libncurses-dev unixodbc-dev && \
    curl https://mise.run | sh

WORKDIR /app

RUN --mount=type=bind,source=.mise.toml,target=/app/mise.toml \
    mise x elixir erlang -- mix local.hex --force && \
    mise x elixir erlang -- mix local.rebar --force

RUN --mount=type=bind,source=.mise.toml,target=/app/mise.toml \
    --mount=type=bind,source=mix.exs,target=/app/mix.exs \
    --mount=type=bind,source=mix.lock,target=/app/mix.lock \
    mix deps.get --only-prod && \
    mix deps.clean --unused && \
    mix deps.compile

COPY . .


CMD ["sh", "-c", "iex --name ${RELEASE_NODE} --cookie nosecret -S mix run -e 'FlameK8sBackend.IntegrationTestRunner.runner()'"]
