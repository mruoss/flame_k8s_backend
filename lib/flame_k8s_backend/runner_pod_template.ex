defmodule FLAMEK8sBackend.RunnerPodTemplate do
  @moduledoc ~S'''
  This module is responsible for generating the manifest for the runner pods.

  The manifest can be overridden using the `runner_pod_tpl` option on
  `FLAMEK8sBackend`.

  ### Simple Use Case

  By default, `resources` and `env` variables are copied from the parent pod.
  Using the `runner_pod_tpl` option on the `FLAMEK8sBackend`, you can add
  additional environment variables or set different `resources`. You would do
  this by setting the `runner_pod_tpl` to a struct of type
  `t:FLAMEK8sBackend.RunnerPodTemplate.t/0` as follows:

  ```
  # application.ex
  alias FLAMEK8sBackend.RunnerPodTemplate

  children = [
    {FLAME.Pool,
      name: MyApp.SamplePool,
      backend: {FLAMEK8sBackend,
        runner_pod_tpl: %RunnerPodTemplate{
          env: [%{"name" => "FOO", "value" => "bar"}],
          resources: %{
            requests: %{"memory" => "256Mi", "cpu" => "100m"},
            limits: %{"memory" => "256Mi", "cpu" => "400m"}
          }
        }
      },
      # other opts
    }
  ]
  # ...
  ```

  ### Advanced Use Cases

  In some cases you might need advanced control over the runner pod manifest.
  Maybe you want to set node affinity because you need your runners to run on
  nodes with GPUs or you need additional volumes etc. In this case, you can set
  the `:manifest` field on the `RunnerPodTemplate` struct, or even use a callback
  function as described below.

  #### Using a Manifest Map

  You can set `:manifest` to a map representing the manifest of the runner Pod:


  ```
  # application.ex
  alias FLAMEK8sBackend.RunnerPodTemplate
  import YamlElixir.Sigil

  manifest = ~y"""
  apiVersion: v1
  kind: Pod
  metadata:
    # your metadata
  spec:
    # Pod spec
  """

  children = [
    {FLAME.Pool,
      name: MyApp.SamplePool,
      backend: {FLAMEK8sBackend, runner_pod_tpl: %RunnerPodTemplate{manifest: manifest}},
      # other opts
    }
  ]
  # ...
  ```

  #### Using a Callback Function

  The callback has to be of type
  `t:FLAMEK8sBackend.RunnerPodTemplate.callback/0`. The callback will be called
  with the manifest of the parent pod which can be used to extract information.
  It should return a pod template as a map

  Define a callback, e.g. in a separate module:

  ```
  defmodule MyApp.FLAMERunnerPodTemplate do
    def runner_pod_template(parent_pod_manifest) do
      manifest = %{
        "metadata" =>
          %{
            #  namespace, labels, ownerReferences,...
          },
        "spec" => %{
          "containers" => [
            %{
              # container definition
            }
          ]
        }
      }

      %RunnerPodTemplate{manifest: manifest}
    end
  end
  ```

  Register the backend:

  ```
  # application.ex
  # ...

  children = [
    {FLAME.Pool,
      name: MyApp.SamplePool,
      backend: {FLAMEK8sBackend, runner_pod_tpl: &MyApp.FLAMERunnerPodTemplate.runner_pod_template/1},
      # other opts
    }
  ]
  # ...
  ```

  > #### Predefined Values {: .warning}
  >
  > Note that the following values are controlled by the backend and, if set in
  > your template, are going to be overwritten:
  >
  >   * `apiVersion` and `Kind` of the resource (set to `v1/Pod`)
  >   * The pod's and container's names (set to a combination of the parent
  >     pod's name and a random id)
  >   * The `restartPolicy` (set to `Never`)
  >   * The container `image` (set to the image of the parent pod's app
  >     container)

  > #### Automatically Defined Environment Variables {: .info}
  >
  > Some environment variables are defined automatically on the
  > runner pod:
  >
  >   * `POD_IP` is set to the runner Pod's IP address (`.status.podIP`) - (not overridable)
  >   * `POD_NAME` is set to the runner Pod's name (`.metadata.name`) - (not overridable)
  >   * `POD_NAMESPACE` is set to the runner Pod's namespace (`.metadata.namespace`) - (not overridable)
  >   * `PHX_SERVER` is set to `false` - (overridable)
  >   * `FLAME_PARENT` used internally by FLAME - (not overridable)
  >   * `RELEASE_COOKIE` is set to the current node cookie - (overridable)
  >   * `RELEASE_DISTRIBUTION` is set to `"name"`-  (overridable)
  >   * `RELEASE_NODE` is set to `"flame_runner@$(POD_IP)"` - (overridable)

  > #### Configuration Precedence {: .warning}
  >
  > When `:manifest` is set together with other options, the options generally
  > override the manifest.
  >
  > The `:resources` option entirely overrides whatever is set in `:manifest`.
  >
  > Environment variables are merged, according to the following precedence:
  >
  >   * overridable defaults (listed above)
  >   * parent pod env vars, if `:add_parent_env` is set (default behaviour)
  >   * manifest env vars
  >   * env vars passed via the `:env` option
  >   * non-overridable defaults (listed above)

  '''

  alias FLAMEK8sBackend.RunnerPodTemplate

  defstruct [:manifest, :env, :resources, add_parent_env: true]

  @typedoc """
  Describing the Runner Pod Template struct

  ### Fields

  * `:manifest` - a map representing the manifest of the runner Pod.

  * `:env` - a map describing a Pod environment variable declaration
    `%{"name" => "MY_ENV_VAR", "value" => "my_env_var_value"}`

  * `:resources` - Pod resource requests and limits.

  * `:add_parent_env` - If true, all env vars of the main container
    including `envFrom` are copied to the runner pod.
    default: `true`
  """
  @type t :: %__MODULE__{
          manifest: map() | nil,
          env: map() | nil,
          resources: map() | nil,
          add_parent_env: boolean()
        }
  @type parent_pod_manifest :: map()
  @type callback :: (parent_pod_manifest() -> t())

  @doc """
  Generates the POD manifest using information from the parent pod
  and the `runner_pod_tpl` option.

  ### Options

  * `:omit_owner_reference` - Omit generating and appending the parent pod as
    `ownerReference` to the runner pod's metadata

  * `:app_container_name` - name of the container running this application. By
    default, the first container in the list of containers is used.

  """
  @spec manifest(parent_pod_manifest(), t() | callback() | nil, Keyword.t()) :: t()
  def manifest(parent_pod_manifest, template_args_or_callback, parent_ref, opts \\ [])

  def manifest(parent_pod_manifest, template_callback, parent_ref, opts)
      when is_function(template_callback) do
    template_opts = template_callback.(parent_pod_manifest)
    manifest(parent_pod_manifest, template_opts, parent_ref, opts)
  end

  def manifest(parent_pod_manifest, nil, parent_ref, opts) do
    manifest(parent_pod_manifest, %RunnerPodTemplate{}, parent_ref, opts)
  end

  def manifest(parent_pod_manifest, %RunnerPodTemplate{} = template_opts, parent_ref, opts) do
    app_container = app_container(parent_pod_manifest, opts)

    parent_env = List.wrap(if template_opts.add_parent_env, do: app_container["env"])
    parent_env_from = List.wrap(if template_opts.add_parent_env, do: app_container["envFrom"])

    parent_pod_manifest_name = parent_pod_manifest["metadata"]["name"]
    parent_pod_manifest_namespace = parent_pod_manifest["metadata"]["namespace"]

    object_references =
      if opts[:omit_owner_reference],
        do: [],
        else: object_references(parent_pod_manifest)

    parent =
      FLAME.Parent.new(parent_ref, self(), FLAMEK8sBackend, parent_pod_manifest_name, "POD_IP")

    parent =
      case System.get_env("FLAME_K8S_BACKEND_GIT_REF") do
        nil -> parent
        git_ref -> struct(parent, backend_vsn: [github: "mruoss/flame_k8s_backend", ref: git_ref])
      end

    encoded_parent = FLAME.Parent.encode(parent)

    (template_opts.manifest || %{})
    |> Map.merge(%{"apiVersion" => "v1", "kind" => "Pod"})
    |> Map.put_new("metadata", %{})
    |> Map.update!("metadata", fn metadata ->
      metadata
      |> Map.delete("name")
      |> Map.put_new("generateName", parent_pod_manifest_name <> "-")
      |> Map.put_new("namespace", parent_pod_manifest_namespace)
      |> Map.put("ownerReferences", object_references)
    end)
    |> Map.put_new("spec", %{"containers" => [%{}]})
    |> Map.update!("spec", fn spec ->
      spec
      |> Map.put("restartPolicy", "Never")
      |> Map.put_new("serviceAccount", parent_pod_manifest["spec"]["serviceAccount"])
      |> update_in(["containers", Access.at(0)], fn container ->
        container
        |> Map.put("image", app_container["image"])
        |> Map.put("name", "runner")
        # Default to parent resources if not specified.
        |> Map.put_new("resources", app_container["resources"])
        # If :resources option is present, it overrides resources altogether.
        |> put_if_not_nil("resources", template_opts.resources)
        |> Map.put_new("env", [])
        |> Map.update!("env", fn env ->
          # Envs precendence: overridable defaults, parent, template manifest, template :env, non-overridable.
          [
            %{"name" => "PHX_SERVER", "value" => "false"},
            %{"name" => "RELEASE_COOKIE", "value" => Node.get_cookie()},
            %{"name" => "RELEASE_DISTRIBUTION", "value" => "name"},
            %{"name" => "RELEASE_NODE", "value" => "flame_runner@$(POD_IP)"}
          ]
          |> merge_env(parent_env)
          |> merge_env(env)
          |> merge_env(template_opts.env || [])
          |> merge_env([
            %{
              "name" => "POD_NAME",
              "valueFrom" => %{"fieldRef" => %{"fieldPath" => "metadata.name"}}
            },
            %{
              "name" => "POD_IP",
              "valueFrom" => %{"fieldRef" => %{"fieldPath" => "status.podIP"}}
            },
            %{
              "name" => "POD_NAMESPACE",
              "valueFrom" => %{"fieldRef" => %{"fieldPath" => "metadata.namespace"}}
            },
            %{"name" => "FLAME_PARENT", "value" => encoded_parent}
          ])
        end)
        |> Map.put_new("envFrom", [])
        |> Map.update!("envFrom", &(parent_env_from ++ &1))
      end)
    end)
  end

  def manifest(parent_pod_manifest, runner_pod_template, parent_ref, opts)
      when is_map(runner_pod_template) do
    IO.warn("""
    Using a manifest map as :runner_pod_tpl is deprecated. You need to wrap it in a struct instead:

        %RunnerPodTemplate{manifest: manifest_map, add_parent_env: false}

    Note that :add_parent_env defaults to true, so you need to set it to false to maintain the current behaviour.\
    """)

    manifest(
      parent_pod_manifest,
      %RunnerPodTemplate{manifest: runner_pod_template, add_parent_env: false},
      parent_ref,
      opts
    )
  end

  defp put_if_not_nil(map, _key, nil), do: map
  defp put_if_not_nil(map, key, value), do: Map.put(map, key, value)

  defp merge_env([], right), do: right

  defp merge_env(left, right) do
    right_names = for item <- right, into: MapSet.new(), do: item["name"]
    # Envs in right take precedence.
    left = Enum.reject(left, &(&1["name"] in right_names))
    left ++ right
  end

  defp app_container(parent_pod_manifest, opts) do
    container_access =
      case opts[:app_container_name] do
        nil -> []
        name -> [Access.filter(&(&1["name"] == name))]
      end

    parent_pod_manifest
    |> get_in(["spec", "containers" | container_access])
    |> List.first()
  end

  defp object_references(parent_pod_manifest) do
    [
      %{
        "apiVersion" => parent_pod_manifest["apiVersion"],
        "kind" => parent_pod_manifest["kind"],
        "name" => parent_pod_manifest["metadata"]["name"],
        "namespace" => parent_pod_manifest["metadata"]["namespace"],
        "uid" => parent_pod_manifest["metadata"]["uid"]
      }
    ]
  end
end
