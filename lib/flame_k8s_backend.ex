defmodule FLAMEK8sBackend do
  @moduledoc """
  Kubernetes Backend implementation. In order for this to work, your application
  needs to meet some requirements.

  ### Usage

  Configure the flame backend in our configuration.

  ```
  # config.exs
  if config_env() == :prod do
    config :flame, :backend, FLAMEK8sBackend
    config :flame, FLAMEK8sBackend, log: :debug
  end
  ```

  ### Env Variables

  In order for the backend to be able to get informations from your pod and use
  them for  the runner pods (e.g. env variables), you have to define `POD_NAME`
  and `POD_NAMESPACE` environment variables on your pod.

  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  spec:
  selector:
    matchLabels:
      app: myapp
  template:
    spec:
      containers:
        - env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.namespace
  ```

  ### RBAC

  Your application needs run as a service account with permissions to manage
  pods. This is a simple

  ```yaml
  ---
  apiVersion: v1
  kind: ServiceAccount
  metadata:
  name: myapp
  namespace: app-namespace
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
  namespace: app-namespace
  name: pod-mgr
  rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "delete", "patch"]
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
  metadata:
  name: myapp-pod-mgr
  namespace: app-namespace
  subjects:
  - kind: ServiceAccount
    name: myapp
    namespace: app-namespace
  roleRef:
  kind: Role
  name: pod-mgr
  apiGroup: rbac.authorization.k8s.io
  ---
  apiVersion: apps/v1
  kind: Deployment
  spec:
  template:
    spec:
      serviceAccountName: flame-test
  ```

  ### Clustering

  Your application needs to be able to form a cluster with your runners. Define
  `POD_IP`, `RELEASE_DISTRIBUTION` and `RELEASE_NODE` environment variables on
  your pods as follows:

  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  spec:
  template:
    spec:
      containers:
        - env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: status.podIP
            - name: RELEASE_DISTRIBUTION
              value: name
            - name: RELEASE_NODE
              value: flame_test@$(POD_IP)
  ```
  """
  @behaviour FLAME.Backend

  alias FLAMEK8sBackend.K8sClient

  require Logger

  defstruct token_path: "/var/run/secrets/kubernetes.io/serviceaccount",
            env: %{},
            base_pod: nil,
            parent_ref: nil,
            runner_node_basename: nil,
            runner_pod_ip: nil,
            runner_pod_name: nil,
            runner_node_name: nil,
            boot_timeout: nil,
            container_name: nil,
            remote_terminator_pid: nil,
            log: false,
            req: nil

  @valid_opts ~w(token_path container_name terminator_sup log)a
  @required_config ~w()a

  @impl true
  def init(opts) do
    :global_group.monitor_nodes(true)
    conf = Application.get_env(:flame, __MODULE__) || []
    [node_base | _ip] = node() |> to_string() |> String.split("@")

    default = %FLAMEK8sBackend{
      boot_timeout: 30_000,
      runner_node_basename: node_base
    }

    provided_opts =
      conf
      |> Keyword.merge(opts)
      |> Keyword.validate!(@valid_opts)

    state = struct(default, provided_opts)

    for key <- @required_config do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    parent_ref = make_ref()

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__)
      |> FLAME.Parent.encode()

    new_env =
      Map.merge(
        %{PHX_SERVER: "false", FLAME_PARENT: encoded_parent},
        state.env
      )

    {:ok, req} = K8sClient.connect(state.token_path, insecure_skip_tls_verify: true)

    case K8sClient.get_pod(req, System.get_env("POD_NAMESPACE"), System.get_env("POD_NAME")) do
      {:ok, base_pod} ->
        new_state =
          struct(state, req: req, base_pod: base_pod, env: new_env, parent_ref: parent_ref)

        {:ok, new_state}

      {:error, error} ->
        Logger.error(Exception.message(error))
        {:error, error}
    end
  end

  @impl true
  def remote_spawn_monitor(%FLAMEK8sBackend{} = state, term) do
    case term do
      func when is_function(func, 0) ->
        {pid, ref} = Node.spawn_monitor(state.runner_node_name, func)
        {:ok, {pid, ref}}

      {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
        {pid, ref} = Node.spawn_monitor(state.runner_node_name, mod, fun, args)
        {:ok, {pid, ref}}

      other ->
        raise ArgumentError,
              "expected a null arity function or {mod, func, args}. Got: #{inspect(other)}"
    end
  end

  @impl true
  def system_shutdown do
    System.stop()
  end

  @impl true
  def remote_boot(%FLAMEK8sBackend{parent_ref: parent_ref} = state) do
    log(state, "Remote Boot")

    {new_state, req_connect_time} =
      with_elapsed_ms(fn ->
        created_pod =
          state
          |> create_runner_pod()
          |> then(&K8sClient.create_pod!(state.req, &1, state.boot_timeout))

        log(state, "Pod Created and Scheduled")

        case created_pod do
          {:ok, pod} ->
            log(state, "Pod Scheduled. IP: #{pod["status"]["podIP"]}")

            struct!(state,
              runner_pod_ip: pod["status"]["podIP"],
              runner_pod_name: pod["metadata"]["name"]
            )

          :error ->
            Logger.error("failed to schedule runner pod within #{state.boot_timeout}ms")
            exit(:timeout)
        end
      end)

    remaining_connect_window = state.boot_timeout - req_connect_time
    runner_node_name = :"#{state.runner_node_basename}@#{new_state.runner_pod_ip}"

    log(state, "Waiting for Remote UP. Remaining: #{remaining_connect_window}")

    remote_terminator_pid =
      receive do
        {^parent_ref, {:remote_up, remote_terminator_pid}} ->
          log(state, "Remote is Up!")
          remote_terminator_pid
      after
        remaining_connect_window ->
          Logger.error("failed to connect to runner pod within #{state.boot_timeout}ms")
          exit(:timeout)
      end

    new_state =
      struct!(new_state,
        remote_terminator_pid: remote_terminator_pid,
        runner_node_name: runner_node_name
      )

    {:ok, remote_terminator_pid, new_state}
  end

  @impl true
  def handle_info({:nodedown, down_node}, state) do
    if down_node == state.runner_node_name do
      log(state, "Runner #{state.runner_node_name} Down")
      {:stop, {:shutdown, :noconnection}, state}
    else
      log(state, "Other Runner #{down_node} Down")
      {:noreply, state}
    end
  end

  def handle_info({:nodeup, _}, state), do: {:noreply, state}

  def handle_info({ref, {:remote_shutdown, :idle}}, %{parent_ref: ref} = state) do
    namespace = System.get_env("POD_NAMESPACE")
    runner_pod_name = state.runner_pod_name
    log(state, "Deleting Pod #{namespace}/#{runner_pod_name}")
    K8sClient.delete_pod!(state.req, namespace, runner_pod_name)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    log(state, "Missed message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp create_runner_pod(state) do
    %{base_pod: base_pod, env: env} = state

    pod_name_sliced = base_pod |> get_in(~w(metadata name)) |> String.slice(0..40)
    runner_pod_name = pod_name_sliced <> rand_id(20)

    container_access =
      case state.container_name do
        nil -> []
        name -> [Access.filter(&(&1["name"] == name))]
      end

    base_container = base_pod |> get_in(["spec", "containers" | container_access]) |> List.first()

    %{
      "apiVersion" => "v1",
      "kind" => "Pod",
      "metadata" => %{
        "namespace" => base_pod["metadata"]["namespace"],
        "name" => runner_pod_name,
        "ownerReferences" => [
          %{
            "apiVersion" => base_pod["apiVersion"],
            "kind" => base_pod["kind"],
            "name" => base_pod["metadata"]["name"],
            "uid" => base_pod["metadata"]["uid"]
          }
        ]
      },
      "spec" => %{
        "restartPolicy" => "Never",
        "containers" => [
          %{
            "image" => base_container["image"],
            "name" => runner_pod_name,
            "resources" => base_container["resources"],
            "env" => encode_k8s_env(env) ++ base_container["env"]
          }
        ]
      }
    }
  end

  defp with_elapsed_ms(func) when is_function(func, 0) do
    {micro, result} = :timer.tc(func)
    {result, div(micro, 1000)}
  end

  defp rand_id(len) do
    len
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(padding: false, case: :lower)
    |> binary_part(0, len)
  end

  defp encode_k8s_env(env_map) do
    for {name, value} <- env_map, do: %{"name" => name, "value" => value}
  end

  defp log(%FLAMEK8sBackend{log: false}, _), do: :ok

  defp log(%FLAMEK8sBackend{log: level}, msg, metadata \\ []) do
    Logger.log(level, msg, metadata)
  end
end
