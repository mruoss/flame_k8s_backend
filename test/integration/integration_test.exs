defmodule FlameK8sBackend.IntegrationTest do
  use ExUnit.Case

  setup_all do
    {clusters_out, exit_code} = System.cmd("kind", ~w(get clusters))
    assert 0 == exit_code, "kind is not installed. Please install kind."

    if not (clusters_out
            |> String.split("\n", trim: true)
            |> Enum.member?("flame-integration-test")) do
      exit_code =
        System.cmd("kind", ~w(create cluster --name flame-integration-test),
          stderr_to_stdout: true
        )

      assert 0 == exit_code, "Could not create kind cluster 'flame-integration-test'"
    end

    System.cmd(
      "docker",
      ~w(build -f test/integration/Dockerfile . -t flamek8sbackend:integration),
      stderr_to_stdout: true
    )

    System.cmd(
      "kind",
      ~w(load docker-image --name flame-integration-test flamek8sbackend:integration),
      stderr_to_stdout: true
    )

    System.cmd("kubectl", ~w(config set-context --current kind-flame-integration-test),
      stderr_to_stdout: true
    )

    System.cmd("kubectl", ~w(delete -f test/integration/manifest.yaml), stderr_to_stdout: true)
    System.cmd("kubectl", ~w(apply -f test/integration/manifest.yaml), stderr_to_stdout: true)

    on_exit(fn ->
      System.cmd("kubectl", ~w(delete -f test/integration/manifest.yaml), stderr_to_stdout: true)
    end)

    :ok
  end

  defp assert_logs_eventually(_pattern, timeout) when timeout < 0 do
    :not_found
  end

  defp assert_logs_eventually(pattern, timeout) do
    with {logs, 0} <- System.cmd("kubectl", ~w"-n integration logs integration"),
         true <- Regex.match?(pattern, logs) do
      :ok
    else
      _ ->
        Process.sleep(300)
        assert_logs_eventually(pattern, timeout - 300)
    end
  end

  # Integration test setup builds a docker image which starts the FLAME pools
  # defined in FlameK8sBackend.IntegrationTestRunner and starts a runner for
  #  each pool. It then logs the result. These checks "just" check that the logs
  #  statements are actually visible on the pod logs:
  @tag :integration
  test "Pod shows the log statement with the result of the first runner " do
    assert :ok == assert_logs_eventually(~r/Result is :flame_ok/, 30_000),
           "Logs were not found"
  end

  @tag :integration
  test "Pod shows the log statement with the result of the first runner" do
    assert :ok == assert_logs_eventually(~r/Result is "foobar"/, 30_000),
           "Logs were not found"
  end
end
