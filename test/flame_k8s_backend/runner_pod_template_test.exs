defmodule FLAMEK8sBackend.RunnerPodTemplateTest do
  use ExUnit.Case

  alias FLAMEK8sBackend.RunnerPodTemplate, as: MUT
  alias FLAMEK8sBackend.TestSupport.Pods

  import YamlElixir.Sigil

  defp flame_parent(pod_manifest) do
    pod_manifest
    |> get_in(env_var_access("FLAME_PARENT"))
    |> List.first()
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end

  defp env_var_access(name) do
    app_container_access(["env", Access.filter(&(&1["name"] == name)), "value"])
  end

  defp app_container_access(field \\ []),
    do: ["spec", "containers", Access.at(0)] ++ List.wrap(field)

  setup_all do
    [parent_pod_manifest_full: Pods.parent_pod_manifest_full()]
  end

  describe "manifest/2" do
    alias FLAMEK8sBackend.TestSupport.Pods

    test "should return pod manifest with data form callback", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      callback = fn parent_manifest, app_container ->
        assert parent_manifest == parent_pod_manifest
        assert get_in(parent_manifest, app_container_access()) == app_container

        ~y"""
        metadata:
          namespace: test
        spec:
          containers:
            - resources:
                limits:
                  memory: 500Mi
                  cpu: 500
              env:
                - name: FOO
                  value: "bar"
        """
        |> put_in(
          app_container_access(~w(resources requests)),
          get_in(parent_manifest, app_container_access(~w(resources requests)))
        )
      end

      pod_manifest = MUT.manifest(parent_pod_manifest, callback, make_ref())

      # sets defaults for required ENV vars
      assert get_in(pod_manifest, env_var_access("PHX_SERVER")) == ["false"]
      assert get_in(pod_manifest, env_var_access("RELEASE_DISTRIBUTION")) == ["name"]
      assert get_in(pod_manifest, env_var_access("RELEASE_NODE")) == ["flame_runner@$(POD_IP)"]

      # from the callback
      assert get_in(pod_manifest, env_var_access("FOO")) == ["bar"]
      assert get_in(pod_manifest, app_container_access(~w(resources requests memory))) == "100Mi"
      assert get_in(pod_manifest, app_container_access(~w(resources limits memory))) == "500Mi"
    end

    test "should add default data to pod manifest", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      manifest = ~y"""
      metadata:
        namespace: test
      spec:
        containers:
          - resources:
              limits:
                memory: 500Mi
                cpu: 500
      """

      pod_manifest = MUT.manifest(parent_pod_manifest, manifest, make_ref())
      assert get_in(pod_manifest, app_container_access() ++ ["image"]) == "flame-test-image:0.1.0"

      owner_references = get_in(pod_manifest, ~w(metadata ownerReferences))
      assert length(owner_references) == 1
      owner_reference = List.first(owner_references)
      assert owner_reference["kind"] == "Pod"
      assert owner_reference["name"] == "flame-cb76858b7-ms8nd"
    end

    test "should take data from container with given app_container_name", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      manifest = ~y"""
      metadata:
        namespace: test
      spec:
        containers:
          - resources:
              limits:
                memory: 500Mi
                cpu: 500
      """

      pod_manifest =
        MUT.manifest(parent_pod_manifest, manifest, make_ref(),
          app_container_name: "other-container"
        )

      assert get_in(pod_manifest, app_container_access() ++ ["image"]) == "other-image:0.1.0"
    end

    test "should not add ownerReferences if omitted", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      manifest = ~y"""
      metadata:
        namespace: test
      spec:
        containers:
          - resources:
              limits:
                memory: 500Mi
                cpu: 500
      """

      pod_manifest =
        MUT.manifest(parent_pod_manifest, manifest, make_ref(), omit_owner_reference: true)

      assert [] == get_in(pod_manifest, ~w(metadata ownerReferences))
    end

    test "env precedence", %{parent_pod_manifest_full: parent_pod_manifest} do
      manifest = ~y"""
      spec:
        containers:
          - env:
              - name: PHX_SERVER
                value: "true"
              - name: FOO
                value: foo_from_manifest
              - name: BAR
                value: bar_from_manifest
      """

      env = %{"BAR" => "bar_from_env_opt", "FLAME_PARENT" => "foo"}

      ref = make_ref()
      pod_manifest = MUT.manifest(parent_pod_manifest, manifest, ref, env: env)

      # FOO comes from manifest, overriding the overridable default
      assert get_in(pod_manifest, env_var_access("PHX_SERVER")) == ["true"]
      # FOO comes from manifest
      assert get_in(pod_manifest, env_var_access("FOO")) == ["foo_from_manifest"]
      # BAR from :env option, overriding BAR from manifest
      assert get_in(pod_manifest, env_var_access("BAR")) == ["bar_from_env_opt"]

      # FLAME_PARENT from :env is ignored, keeping the expected value
      parent = flame_parent(pod_manifest)
      assert parent.ref == ref
    end
  end
end
