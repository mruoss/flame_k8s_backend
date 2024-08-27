defmodule FLAMEK8sBackend.RunnerPodTemplate do
  @moduledoc """

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
            limimts: %{"memory" => "256Mi", "cpu" => "400m"}
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
  `runner_pod_tpl` to either a map representing the Pod manifest or a callback
  function as described below.

  #### Using a Manifest Map

  You can set `runner_pod_tpl` to a map representing the manifest of the runner
  Pod:


  ```
  # application.ex
  alias FLAMEK8sBackend.RunnerPodTemplate
  import YamlElixir.Sigil

  pod_template = ~y\"""
  apiVersion: v1
  kind: Pod
  metadata:
    # your metadata
  spec:
    # Pod spec
  \"""

  children = [
    {FLAME.Pool,
      name: MyApp.SamplePool,
      backend: {FLAMEK8sBackend, runner_pod_tpl: pod_template},
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
    def runner_pod_manifest(parent_pod_manifest) do
      %{
        "metadata" => %{
          # namespace, labels, ownerReferences,...
        },
        "spec" => %{
          "containers" => [
            %{
              # container definition
            }
          ]
        }
      }
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
      backend: {FLAMEK8sBackend, runner_pod_tpl: &MyApp.FLAMERunnerPodTemplate.runner_pod_manifest/1},
      # other opts
    }
  ]
  # ...
  ```

  > #### Predefined Values {: .warning}
  >
  > Note that the following values are controlled by the backend and, if set by
  > your callback function, are going to be overwritten:
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
  >   * `PHX_SERVER` is set to `false` (overridable)
  >   * `FLAME_PARENT` used internally by FLAME - (not overridable)

  ### Options

  * `:omit_owner_reference` - Omit generating and appending the parent pod as
    `ownerReference` to the runner pod's metadata

  * `:app_container_name` - name of the container running this application. By
    default, the first container in the list of containers is used.
  """

  alias FLAMEK8sBackend.RunnerPodTemplate

  defstruct [:env, :resources, add_parent_env: true]

  @typedoc """
  Describing the Runner Pod Template struct

  ### Fields

  * `env` - a map describing a Pod environment variable declaration
    `%{"name" => "MY_ENV_VAR", "value" => "my_env_var_value"}`

  * `resources` - Pod resource requests and limits.

  * `add_parent_env` - If true, all env vars of the main container
    including `envFrom` are copied to the runner pod.
    default: `true`
  """
  @type t :: %__MODULE__{
          env: map() | nil,
          resources: map() | nil,
          add_parent_env: boolean()
        }
  @type parent_pod_manifest :: map()
  @type callback :: (parent_pod_manifest() -> runner_pod_template :: map())

  @doc """
  Generates the POD manifest using information from the parent pod
  and the `runner_pod_tpl` option.
  """
  @spec manifest(parent_pod_manifest(), t() | callback(), Keyword.t()) ::
          runner_pod_template :: map()
  def manifest(parent_pod_manifest, template_args_or_callback, parent_ref, opts \\ [])

  def manifest(parent_pod_manifest, template_callback, parent_ref, opts)
      when is_function(template_callback) do
    app_container = app_container(parent_pod_manifest, opts)

    parent_pod_manifest
    |> template_callback.()
    |> apply_defaults(parent_pod_manifest, app_container, parent_ref, opts)
  end

  def manifest(parent_pod_manifest, nil, parent_ref, opts) do
    manifest(parent_pod_manifest, %RunnerPodTemplate{}, parent_ref, opts)
  end

  def manifest(parent_pod_manifest, %RunnerPodTemplate{} = template_opts, parent_ref, opts) do
    app_container = app_container(parent_pod_manifest, opts)
    env = template_opts.env || []

    parent_env = if template_opts.add_parent_env, do: app_container["env"]
    parent_env_from = if template_opts.add_parent_env, do: app_container["envFrom"]

    runner_pod_template = %{
      "metadata" => %{
        "namespace" => parent_pod_manifest["metadata"]["namespace"]
      },
      "spec" => %{
        "containers" => [
          %{
            "resources" => template_opts.resources || app_container["resources"],
            "env" => env ++ List.wrap(parent_env),
            "envFrom" => List.wrap(parent_env_from)
          }
        ]
      }
    }

    apply_defaults(runner_pod_template, parent_pod_manifest, app_container, parent_ref, opts)
  end

  def manifest(parent_pod_manifest, runner_pod_template, parent_ref, opts)
      when is_map(runner_pod_template) do
    app_container = app_container(parent_pod_manifest, opts)
    apply_defaults(runner_pod_template, parent_pod_manifest, app_container, parent_ref, opts)
  end

  defp apply_defaults(
         runner_pod_template,
         parent_pod_manifest,
         app_container,
         parent_ref,
         opts
       ) do
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

    runner_pod_template
    |> Map.merge(%{"apiVersion" => "v1", "kind" => "Pod"})
    |> update_in([Access.key("metadata", %{})], fn metadata ->
      metadata
      |> Map.delete("name")
      |> Map.put_new("generateName", parent_pod_manifest_name <> "-")
      |> Map.put_new("namespace", parent_pod_manifest_namespace)
      |> Map.put("ownerReferences", object_references)
    end)
    |> put_in(~w(spec restartPolicy), "Never")
    |> update_in(~w(spec), fn spec ->
      spec
      |> Map.put("restartPolicy", "Never")
      |> Map.put_new("serviceAccount", parent_pod_manifest["spec"]["serviceAccount"])
      |> update_in(["containers", Access.at(0)], fn container ->
        container
        |> Map.put("image", app_container["image"])
        |> Map.put("name", "runner")
        |> Map.put_new("env", [])
        |> Map.update!("env", fn env ->
          [
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
            | Enum.reject(
                env,
                &(&1["name"] in ["FLAME_PARENT", "POD_NAME", "POD_NAMESPACE", "POD_IP"])
              )
          ]
          |> put_new_env("PHX_SERVER", "false")
        end)
      end)
    end)
  end

  defp put_new_env(env, name, value) do
    case get_in(env, [Access.filter(&(&1["name"] == name))]) do
      [] -> [%{"name" => name, "value" => value} | env]
      _ -> env
    end
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
