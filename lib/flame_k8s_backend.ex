defmodule FLAMEK8sBackend do
  @moduledoc ~S'''
  Kubernetes Backend implementation.

  ## Usage

  Configure the flame backend in our configuration or application setup:

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

  ## Options

  The following backend options are supported:

    * `:manifest` - If given, specifies the runner pod manifest. This can be
      either of:

        * a manifest map

        * an arity-2 function - it accepts the parent pod manifest and the app
          container part of the manifest (as determined by the `:app_container_name`
          option)

      See the "Manifest configuration" section below for more details.

    * `:env` - A map with environment variables that should be passed to the
      runner. When specified, these environment variables take precendence over
      the ones defined in `:manifest`. This option is a convenience for passing
      extra values read at runtime.

    * `:app_container_name` - If your application pod runs multiple containers
      (initContainers excluded), use this option to pass the name of the
      container running this application. If not given, the first container
      in the list of containers is used to lookup the container image to be used
      for the runner pods.

    * `:omit_owner_reference` - If true, no ownerReferences are configured on
      the runner pods. Defaults to `false`

    * `:log` - The log level to use for verbose logging. Defaults to `false`.

  ## Prerequisites

  In order for this to work, your application needs to meet some requirements.

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
        serviceAccountName: my-app
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
            value: my_app@$(POD_IP)
  ```

  ## Manifest Configuration

  You have full control over the runner pod manifest. For example, to set some
  environment variables and resources, you can do the following:

      manifest = %{
        "spec" => %{
          "containers" => [
            %{
              "env" => [
                %{"name" => "FOO", "value" => "bar"}
              ],
              "resources" => %{
                "requests" => %{"memory" => "256Mi", "cpu" => "100m"},
                "limits" => %{"memory" => "256Mi", "cpu" => "400m"}
              }
            }
          ]
        }
      }

      {FLAME.Pool,
       name: MyApp.SamplePool,
       backend: {FLAMEK8sBackend, manifest: manifest}}

  For more complex manifests, it is convenient to write the manifest as YAML.
  To do that, you can added the `:yaml_elixir` package, and use the `~y` sigil:

      manifest = ~y"""
      metadata:
        spec:
          containers:
            - resources:
                requests:
                  memory: 256Mi
                  cpu: 100m
                limits:
                  memory: 256Mi
                  cpu: 400m
            - env:
                - name: FOO
                  value: bar
      """

      {FLAME.Pool,
       name: MyApp.SamplePool,
       backend: {FLAMEK8sBackend, manifest: manifest}}

  You may want to automatically copy certain configuration from the parent pod.
  To do that, you can pass a function to build the manifest:

      manifest_fun = fn parent_pod_manifest, app_container ->
        %{
          "metadata" => %{
            # ...
          },
          "spec" => %{
            "containers" => [
              %{
                # Copy all env vars and resources from the parent container definition.
                "env" => app_container["env"] || [],
                "envFrom" => app_container["envFrom"] || [],
                "resources" => app_container["resources"] || %{}
              }
            ]
          }
        }
      end

      {FLAME.Pool,
       name: MyApp.SamplePool,
       backend: {FLAMEK8sBackend, manifest: manifest_fun}}

  > #### Predefined Values {: .warning}
  >
  > Note that the following values are controlled by the backend and, if set in
  > your manifest, are going to be overwritten:
  >
  >   * `apiVersion` and `Kind` of the resource (set to `v1/Pod`)
  >   * The pod's and container's names (set to a combination of the parent
  >     pod's name and a random id)
  >   * The `restartPolicy` (set to `Never`)
  >   * The container `image` (set to the image of the parent pod's app
  >     container)

  > #### Automatically Defined Environment Variables {: .info}
  >
  > Some environment variables are defined automatically on the runner pod:
  >
  >   * `POD_IP` is set to the runner Pod's IP address (`.status.podIP`) - (not overridable)
  >   * `POD_NAME` is set to the runner Pod's name (`.metadata.name`) - (not overridable)
  >   * `POD_NAMESPACE` is set to the runner Pod's namespace (`.metadata.namespace`) - (not overridable)
  >   * `PHX_SERVER` is set to `false` - (overridable)
  >   * `FLAME_PARENT` used internally by FLAME - (not overridable)
  >   * `RELEASE_COOKIE` is set to the current node cookie - (overridable)
  >   * `RELEASE_DISTRIBUTION` is set to `"name"`-  (overridable)
  >   * `RELEASE_NODE` is set to `"flame_runner@$(POD_IP)"` - (overridable)

  > #### Environment Variables Precedence {: .warning}
  >
  > Environment variables from multiple sources are merged, according to the
  > following precedence:
  >
  >   * overridable defaults (listed above)
  >   * env vars defined in `:manifest`
  >   * env vars passed via the `:env` option
  >   * non-overridable defaults (listed above)

  '''

  @behaviour FLAME.Backend

  alias FLAMEK8sBackend.K8sClient
  alias FLAMEK8sBackend.RunnerPodTemplate

  require Logger

  defstruct runner_pod_manifest: nil,
            parent_ref: nil,
            runner_node_name: nil,
            manifest: nil,
            env: nil,
            boot_timeout: nil,
            remote_terminator_pid: nil,
            omit_owner_reference: false,
            log: false,
            http: nil

  @valid_opts ~w(app_container_name manifest env terminator_sup log boot_timeout omit_owner_reference)a
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
                provided_opts[:manifest] || %{},
                parent_ref,
                Keyword.take(provided_opts, [:env, :app_container_name, :omit_owner_reference])
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
