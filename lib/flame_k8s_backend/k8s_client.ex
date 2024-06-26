defmodule FLAMEK8sBackend.K8sClient do
  @moduledoc false

  @sa_token_path "/var/run/secrets/kubernetes.io/serviceaccount"
  @pod_tpl "/api/v1/namespaces/:namespace/pods/:name"
  @pod_list_tpl "/api/v1/namespaces/:namespace/pods"

  def connect() do
    ca_cert_path = Path.join(@sa_token_path, "ca.crt")
    token_path = Path.join(@sa_token_path, "token")
    apiserver_host = System.get_env("KUBERNETES_SERVICE_HOST")
    apiserver_port = System.get_env("KUBERNETES_SERVICE_PORT_HTTPS")
    token = File.read!(token_path)

    req =
      Req.new(
        base_url: "https://#{apiserver_host}:#{apiserver_port}",
        headers: [{:Authorization, "Bearer #{token}"}],
        connect_options: [
          transport_opts: [
            cacertfile: String.to_charlist(ca_cert_path)
          ]
        ]
      )
      |> Req.Request.append_response_steps(verify_2xs: &verify_2xs/1)

    req
  end

  def get_pod!(req, namespace, name) do
    Req.get!(req, url: @pod_tpl, path_params: [namespace: namespace, name: name]).body
  end

  def get_pod(req, namespace, name) do
    with {:ok, %{body: body}} <-
           Req.get(req, url: @pod_tpl, path_params: [namespace: namespace, name: name]),
         do: {:ok, body}
  end

  def delete_pod!(req, namespace, name) do
    Req.delete!(req, url: @pod_tpl, path_params: [namespace: namespace, name: name])
  end

  def create_pod!(req, pod, timeout) do
    name = pod["metadata"]["name"]
    namespace = pod["metadata"]["namespace"]
    Req.post!(req, url: @pod_list_tpl, path_params: [namespace: namespace], json: pod)
    wait_until_scheduled(req, namespace, name, timeout)
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

  defp verify_2xs({request, response}) do
    if response.status in 200..299 do
      {request, response}
    else
      {request, RuntimeError.exception(response.body["message"])}
    end
  end
end
