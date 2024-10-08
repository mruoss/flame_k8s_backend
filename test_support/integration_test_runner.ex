defmodule FlameK8sBackend.IntegrationTestRunner do
  require Logger

  import YamlElixir.Sigil

  def setup() do
    Application.ensure_all_started(:flame)

    pod_template_callback = fn _ ->
      ~y"""
      spec:
        containers:
        - env:
          - name: "FOO"
            value: "foobar"
      """
    end

    children = [
      {
        FLAME.Pool,
        name: IntegrationTest.Runner,
        min: 0,
        max: 2,
        max_concurrency: 10,
        boot_timeout: :timer.minutes(3),
        idle_shutdown_after: :timer.minutes(1),
        timeout: :infinity,
        backend: FLAMEK8sBackend,
        track_resources: true,
        log: :debug
      },
      {
        FLAME.Pool,
        name: IntegrationTest.CallbackRunner,
        min: 0,
        max: 2,
        max_concurrency: 10,
        boot_timeout: :timer.minutes(3),
        idle_shutdown_after: :timer.minutes(1),
        timeout: :infinity,
        backend: {FLAMEK8sBackend, runner_pod_tpl: pod_template_callback},
        track_resources: true,
        log: :debug
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def run_flame() do
    setup()

    [
      {IntegrationTest.Runner, fn -> :flame_ok end},
      {IntegrationTest.CallbackRunner, fn -> System.get_env("FOO") end}
    ]
    |> Enum.map(fn {pool, fun} -> Task.async(fn -> FLAME.call(pool, fun) end) end)
    |> Task.await_many(:infinity)
    |> Enum.each(fn result -> Logger.info("Result is #{inspect(result)}") end)
  end

  def runner() do
    setup()
    Process.sleep(60_000)
  end
end
