defmodule FlameK8sBackend.IntegrationTest do
  use ExUnit.Case

  setup_all do
    {clusters_out, exit_code} = System.cmd("kind", ~w(get clusters))
    assert 0 == exit_code, "kind is not installed. Please install kind."

    if not (clusters_out
            |> String.split("\n", trim: true)
            |> Enum.member?("flame-integration-test")) do
      exit_code = Mix.Shell.IO.cmd("kind create cluster --name flame-integration-test")
      assert 0 == exit_code, "Could not create kind cluster 'flame-integration-test'"
    end

    Mix.Shell.IO.cmd(
      "docker build -f test/integration/Dockerfile . -t flamek8sbackend:integration"
    )

    Mix.Shell.IO.cmd(
      "kind load docker-image --name flame-integration-test flamek8sbackend:integration"
    )

    Mix.Shell.IO.cmd("kubectl config set-context --current kind-flame-integration-test")
    Mix.Shell.IO.cmd("kubectl delete -f test/integration/manifest.yaml")
    Mix.Shell.IO.cmd("kubectl apply -f test/integration/manifest.yaml")

    on_exit(fn ->
      Mix.Shell.IO.cmd("kubectl delete -f test/integration/manifest.yaml")
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

  @tag :integration
  test "check the logs" do
    assert :ok == assert_logs_eventually(~r/Result is :flame_ok/, 30_000),
           "Logs were not found"
  end
end
