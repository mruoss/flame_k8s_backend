defmodule FLAMEK8sBackend do
  @moduledoc """
  Kubernetes Backend implementation.

  ### Usage

  Configure the flame backend in our configuration or application setup:

  ```
  # application.ex
  children = [
    {FLAME.Pool,
      name: MyApp.SamplePool,
      backend: FLAMEK8sBackend,
      min: 0,
      max: 10,
      max_concurrency: 5,
      idle_shutdown_after: 30_000}
  ]
  ```

  ### Options

  The following backend options are supported:

    * `:app_container_name` - If your application pod runs multiple containers
      (initContainers excluded), use this option to pass the name of the
      container running this application. If not given, the first container
      in the list of containers is used to lookup the contaienr image, env vars
      and resources to be used for the runner pods.

    * `:omit_owner_reference` - If true, no ownerReferences are configured on
      the runner pods. Defaults to `false`

    * `:runner_pod_tpl` - If given, controls how the runner pod manifest is
      generated. Can be a function of type
      `t:FLAMEK8sBackend.RunnerPodTemplate.callback/0` or a struct of type
      `t:FLAMEK8sBackend.RunnerPodTemplate.t/0`.
      A callback receives the manifest of the parent pod as a map and should
      return the runner pod's manifest as a map().
      If a struct is given, the runner pod's manifest will be generated with
      values from the struct if given or from the parent pod if omitted.
      If this option is omitted, the parent pod's `env` and `resources`
      are used for the runner pod.
      See `FLAMEK8sBackend.RunnerPodTemplate` for more infos.

    * `:log` - The log level to use for verbose logging. Defaults to `false`.

  ### Prerequisites

  In order for this to work, your application needs to meet some requirements.

  #### Env Variables

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

  #### RBAC

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
        serviceAccountName: my-app
  ```

  #### Clustering

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
            value: my_app@$(POD_IP)
  ```
  """
  @behaviour FLAME.Backend

  alias FLAMEK8sBackend.K8sClient
  alias FLAMEK8sBackend.RunnerPodTemplate

  require Logger

  defstruct runner_pod_manifest: nil,
            parent_ref: nil,
            runner_node_name: nil,
            runner_pod_tpl: nil,
            boot_timeout: nil,
            remote_terminator_pid: nil,
            log: false,
            http: nil

  @valid_opts ~w(app_container_name runner_pod_tpl terminator_sup log boot_timeout)a
  @required_config ~w()a

  @impl true
  def init(opts) do
    conf = Application.get_env(:flame, __MODULE__) || []
    [_node_base | _ip] = node() |> to_string() |> String.split("@")

    default = %FLAMEK8sBackend{
      boot_timeout: 30_000
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

    http = K8sClient.connect()

    case K8sClient.get_pod(http, System.get_env("POD_NAMESPACE"), System.get_env("POD_NAME")) do
      {:ok, base_pod} ->
        new_state =
          struct(state,
            http: http,
            parent_ref: parent_ref,
            runner_pod_manifest:
              RunnerPodTemplate.manifest(
                base_pod,
                provided_opts[:runner_pod_tpl],
                parent_ref,
                Keyword.take(provided_opts, [:app_container_name, :omit_owner_reference])
              )
          )

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
  def system_shutdown() do
    # This is not very nice but I don't have the opts on the runner
    http = K8sClient.connect()
    namespace = System.get_env("POD_NAMESPACE")
    name = System.get_env("POD_NAME")
    K8sClient.delete_pod!(http, namespace, name)
    System.stop()
  end

  @impl true
  def remote_boot(%FLAMEK8sBackend{parent_ref: parent_ref} = state) do
    log(state, "Remote Boot")

    {new_state, req_connect_time} =
      with_elapsed_ms(fn ->
        created_pod =
          K8sClient.create_pod!(state.http, state.runner_pod_manifest, state.boot_timeout)

        case created_pod do
          {:ok, pod} ->
            log(state, "Runner pod created and scheduled", pod_ip: pod["status"]["podIP"])
            state

          :error ->
            Logger.error("failed to schedule runner pod within #{state.boot_timeout}ms")
            exit(:timeout)
        end
      end)

    remaining_connect_window = state.boot_timeout - req_connect_time

    log(state, "Waiting for Remote UP.", remaining_connect_window: remaining_connect_window)

    remote_terminator_pid =
      receive do
        {^parent_ref, {:remote_up, remote_terminator_pid}} ->
          log(state, "Remote flame is Up!")
          remote_terminator_pid
      after
        remaining_connect_window ->
          Logger.error("failed to connect to runner pod within #{state.boot_timeout}ms")
          exit(:timeout)
      end

    new_state =
      struct!(new_state,
        remote_terminator_pid: remote_terminator_pid,
        runner_node_name: node(remote_terminator_pid)
      )

    {:ok, remote_terminator_pid, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    log(state, "Missed message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp with_elapsed_ms(func) when is_function(func, 0) do
    {micro, result} = :timer.tc(func)
    {result, div(micro, 1000)}
  end

  defp log(state, msg, metadata \\ [])

  defp log(%FLAMEK8sBackend{log: false}, _, _), do: :ok

  defp log(%FLAMEK8sBackend{log: level}, msg, metadata) do
    Logger.log(level, msg, metadata)
  end
end
