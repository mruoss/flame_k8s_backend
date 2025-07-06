defmodule FlameK8sBackend.IntegrationTest do
  use ExUnit.Case

  @k8s_cluster System.get_env("TEST_K8S_CLUSTER", "flame-integration-test")

  setup_all do
    {clusters_out, exit_code} = System.cmd("kind", ~w(get clusters))
    assert 0 == exit_code, "kind is not installed. Please install kind."

    if not (clusters_out
            |> String.split("\n", trim: true)
            |> Enum.member?(@k8s_cluster)) do
      {_, exit_code} =
        System.cmd("kind", ["create", "cluster", "--name", @k8s_cluster], stderr_to_stdout: true)

      assert 0 == exit_code, "Could not create kind cluster '#{@k8s_cluster}'"
    end

    {_, 0} =
      System.cmd(
        "docker",
        ~w(build --memory-swap 2Gi -f test/integration/Dockerfile . -t flamek8sbackend:integration),
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd(
        "kind",
        ["load", "docker-image", "--name", @k8s_cluster, "flamek8sbackend:integration"],
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd("kubectl", ["config", "use-context", "kind-#{@k8s_cluster}"],
        stderr_to_stdout: true
      )

    System.cmd("kubectl", ~w(delete -f test/integration/manifest.yaml), stderr_to_stdout: true)

    {_, 0} =
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
