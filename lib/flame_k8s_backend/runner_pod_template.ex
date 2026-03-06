defmodule FLAMEK8sBackend.RunnerPodTemplate do
  @moduledoc false

  @type parent_pod_manifest :: map()
  @type manifest :: map()
  @type callback :: (parent_pod_manifest() -> manifest())

  @spec manifest(parent_pod_manifest(), manifest() | callback(), Keyword.t()) :: manifest()
  def manifest(parent_pod_manifest, template_args_or_callback, parent_ref, opts \\ [])

  def manifest(parent_pod_manifest, template_callback, parent_ref, opts)
      when is_function(template_callback) do
    app_container = app_container(parent_pod_manifest, opts)
    manifest = template_callback.(parent_pod_manifest, app_container)
    manifest(parent_pod_manifest, manifest, parent_ref, opts)
  end

  def manifest(parent_pod_manifest, manifest, parent_ref, opts) do
    app_container = app_container(parent_pod_manifest, opts)

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

    manifest
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
        |> Map.put_new("env", [])
        |> Map.update!("env", fn env ->
          # Envs precendence: overridable defaults, template manifest, template :env, non-overridable.
          [
            %{"name" => "PHX_SERVER", "value" => "false"},
            %{"name" => "RELEASE_COOKIE", "value" => Node.get_cookie()},
            %{"name" => "RELEASE_DISTRIBUTION", "value" => "name"},
            %{"name" => "RELEASE_NODE", "value" => "flame_runner@$(POD_IP)"}
          ]
          |> merge_env(env)
          |> merge_env_map(opts[:env] || %{})
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
      end)
    end)
  end

  defp merge_env([], right), do: right

  defp merge_env(left, right) do
    right_names = for item <- right, into: MapSet.new(), do: item["name"]
    # Envs in right take precedence.
    left = Enum.reject(left, &(&1["name"] in right_names))
    left ++ right
  end

  defp merge_env_map(env, env_map) when env_map == %{}, do: env

  defp merge_env_map(env, env_map) do
    # Envs in right take precedence.
    left = Enum.reject(env, &Map.has_key?(env_map, &1["name"]))
    right = Enum.map(env_map, fn {key, value} -> %{"name" => key, "value" => value} end)
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
