defmodule FlameK8sBackend.HTTP do
  @moduledoc false

  defstruct [:base_url, :token, :cacertfile]

  @type t :: %__MODULE__{
          base_url: String.t(),
          token: String.t(),
          cacertfile: String.t()
        }

  @spec new(fields :: Keyword.t()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)

  @spec get(t(), path :: String.t()) :: {:ok, map()} | {:error, String.t()}
  def get(http, path), do: request(http, :get, path)

  @spec get!(t(), path :: String.t()) :: map()
  def get!(http, path), do: request!(http, :get, path)

  @spec post!(t(), path :: String.t(), body :: String.t()) :: map()
  def post!(http, path, body), do: request!(http, :post, path, body)

  @spec delete!(t(), path :: String.t()) :: map()
  def delete!(http, path), do: request!(http, :delete, path)

  @spec request!(http :: t(), verb :: atom(), path :: Stringt.t()) :: map()
  defp request!(http, verb, path, body \\ nil) do
    case request(http, verb, path, body) do
      {:ok, response_body} -> Jason.decode!(response_body)
      {:error, reason} -> raise reason
    end
  end

  @spec request(http :: t(), verb :: atom(), path :: String.t(), body :: String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp request(http, verb, path, body \\ nil) do
    headers = [{~c"Authorization", ~c"Bearer #{http.token}"}]
    http_opts = [ssl: [verify: :verify_peer, cacertfile: http.cacertfile]]
    url = http.base_url <> path

    request =
      if is_nil(body),
        do: {url, headers},
        else: {url, headers, ~c"application/json", body}

    case :httpc.request(verb, request, http_opts, []) do
      {:ok, {{_, status, _}, _, response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, {{_, status, reason}, _, resp_body}} ->
        {:error,
         "failed #{String.upcase("#{verb}")} #{url} with #{inspect(status)} (#{inspect(reason)}): #{inspect(resp_body)} #{inspect(headers)}"}

      {:error, reason} ->
        {:error,
         "failed #{String.upcase("#{verb}")} #{url} with #{inspect(reason)} #{inspect(http.headers)}"}
    end
  end
end
