defmodule FLAMEK8sBackend.K8sClient do
  @moduledoc false

  @sa_token_path "/var/run/secrets/kubernetes.io/serviceaccount"

  alias FlameK8sBackend.HTTP

  def connect() do
    ca_cert_path = Path.join(@sa_token_path, "ca.crt")
    token_path = Path.join(@sa_token_path, "token")
    apiserver_host = System.get_env("KUBERNETES_SERVICE_HOST")
    apiserver_port = System.get_env("KUBERNETES_SERVICE_PORT_HTTPS")
    token = File.read!(token_path)

    HTTP.new(
      base_url: "https://#{apiserver_host}:#{apiserver_port}",
      token: token,
      cacertfile: String.to_charlist(ca_cert_path)
    )
  end

  def get_pod!(http, namespace, name) do
    HTTP.get!(http, pod_path(namespace, name))
  end

  def get_pod(http, namespace, name) do
    with {:ok, response_body} <- HTTP.get(http, pod_path(namespace, name)),
         do: Jason.decode(response_body)
  end

  def delete_pod!(http, namespace, name) do
    HTTP.delete!(http, pod_path(namespace, name))
  end

  def create_pod!(http, pod, timeout) do
    name = pod["metadata"]["name"]
    namespace = pod["metadata"]["namespace"]
    HTTP.post!(http, pod_path(namespace, ""), Jason.encode!(pod))
    wait_until_scheduled(http, namespace, name, timeout)
  end

  defp wait_until_scheduled(_req, _namespace, _name, timeout) when timeout <= 0, do: :error

  defp wait_until_scheduled(req, namespace, name, timeout) do
    case get_pod!(req, namespace, name) do
      %{"status" => %{"podIP" => _}} = pod ->
        {:ok, pod}

      _ ->
        Process.sleep(1000)
        wait_until_scheduled(req, namespace, name, timeout - 1000)
    end
  end

  defp pod_path(namespace, name) do
    "/api/v1/namespaces/#{namespace}/pods/#{name}"
  end
end
