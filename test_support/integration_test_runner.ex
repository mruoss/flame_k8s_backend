defmodule FlameK8sBackend.IntegrationTestRunner do
  require Logger

  def setup() do
    Application.ensure_all_started(:flame)

    children = [{
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
        }]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def run_flame() do
    setup()

    result =
      FLAME.call(IntegrationTest.Runner, fn ->
        :flame_ok
      end)

    Logger.info("Result is #{inspect(result)}")
  end

  def runner() do
    setup()
    Process.sleep(60_000)
  end
end
