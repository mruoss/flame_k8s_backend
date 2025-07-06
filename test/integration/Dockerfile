
FROM hexpm/elixir:1.18.4-erlang-28.0.1-debian-bullseye-20250630-slim

ENV MIX_ENV=test \
    MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    DIAGNOSTIC=1

RUN mix local.hex --force && \
    mix local.rebar --force && \
    apt-get update && apt-get install -y git

WORKDIR /app

COPY . .

RUN mix deps.get --only-prod && \
    mix deps.clean --unused && \
    mix deps.compile

CMD ["sh", "-c", "iex --name ${RELEASE_NODE} --cookie nosecret -S mix run -e 'FlameK8sBackend.IntegrationTestRunner.runner()'"]
