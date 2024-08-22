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

  describe "manifest/2 with callback" do
    alias FLAMEK8sBackend.TestSupport.Pods

    test "should pass pod manifest to callback", %{parent_pod_manifest_full: parent_pod_manifest} do
      callback = fn manifest ->
        assert manifest == parent_pod_manifest

        ~y"""
        metadata:
          namespace: test
        spec:
          containers:
            - resources:
                limits:
                  memory: 500Mi
                  cpu: 500
        """
        |> put_in(
          app_container_access(~w(resources requests)),
          get_in(manifest, app_container_access(~w(resources requests)))
        )
      end

      MUT.manifest(parent_pod_manifest, callback, make_ref())
    end

    test "should return pod manifest with data form callback", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      callback = fn parent_pod ->
        ~y"""
        metadata:
          namespace: test
        spec:
          containers:
            - resources:
                limits:
                  memory: 500Mi
                  cpu: 500
        """
        |> put_in(
          app_container_access(~w(resources requests)),
          get_in(parent_pod, app_container_access(~w(resources requests)))
        )
      end

      pod_manifest = MUT.manifest(parent_pod_manifest, callback, make_ref())

      assert get_in(pod_manifest, app_container_access(~w(resources requests memory))) == "100Mi"
      assert get_in(pod_manifest, app_container_access(~w(resources limits memory))) == "500Mi"
    end

    test "should add default data to pod manifest", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      callback = fn _parent_pod ->
        ~y"""
        metadata:
          namespace: test
        spec:
          containers:
            - resources:
                limits:
                  memory: 500Mi
                  cpu: 500
        """
      end

      pod_manifest = MUT.manifest(parent_pod_manifest, callback, make_ref())
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
      callback = fn _parent_pod ->
        ~y"""
        metadata:
          namespace: test
        spec:
          containers:
            - resources:
                limits:
                  memory: 500Mi
                  cpu: 500
        """
      end

      pod_manifest =
        MUT.manifest(parent_pod_manifest, callback, make_ref(),
          app_container_name: "other-container"
        )

      assert get_in(pod_manifest, app_container_access() ++ ["image"]) == "other-image:0.1.0"
    end

    test "should not add ownerReferences if omitted", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      callback = fn _parent_pod ->
        ~y"""
        metadata:
          namespace: test
        spec:
          containers:
            - resources:
                limits:
                  memory: 500Mi
                  cpu: 500
        """
      end

      pod_manifest =
        MUT.manifest(parent_pod_manifest, callback, make_ref(), omit_owner_reference: true)

      assert [] == get_in(pod_manifest, ~w(metadata ownerReferences))
    end
  end

  describe "manifest/2 with map" do
    test "Uses fields defined in pod template", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      pod_template = ~y"""
      apiVersion: v1
      kind: Pod
      metadata:
        namespace: default
      spec:
        containers:
          - name: runner
            resources:
              requests:
                cpu: "1"
      """

      pod_manifest = MUT.manifest(parent_pod_manifest, pod_template, make_ref())

      assert get_in(pod_manifest, app_container_access(~w(name))) == "runner"
      assert get_in(pod_manifest, app_container_access(~w(resources requests cpu))) == "1"
    end
  end

  describe "manifest/2 with empty %RunnerPodTemplate{} struct" do
    test "Uses parent pod's values for empty template opts", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      template_opts = %MUT{}
      pod_manifest = MUT.manifest(parent_pod_manifest, template_opts, make_ref())

      assert get_in(pod_manifest, env_var_access("RELEASE_NODE")) == ["flame_test@$(POD_IP)"]
    end

    test "Only default envs if add_parent_env is set to false", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      ref = make_ref()
      template_opts = %MUT{add_parent_env: false}
      pod_manifest = MUT.manifest(parent_pod_manifest, template_opts, ref)

      assert get_in(pod_manifest, app_container_access(~w(resources requests memory))) == "100Mi"
      assert get_in(pod_manifest, env_var_access("PHX_SERVER")) == ["false"]
      parent = flame_parent(pod_manifest)
      assert parent.ref == ref
    end
  end

  describe "manifest/2 with :env set in %RunnerPodTemplate{}" do
    test "Parent pod's vars are mergd with given vars", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      template_opts = %MUT{env: [%{"name" => "FOO", "value" => "bar"}]}
      pod_manifest = MUT.manifest(parent_pod_manifest, template_opts, make_ref())

      assert get_in(pod_manifest, env_var_access("RELEASE_NODE")) == ["flame_test@$(POD_IP)"]
      assert get_in(pod_manifest, env_var_access("FOO")) == ["bar"]
    end

    test "No parent envs if add_parent_env is set to false", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      template_opts = %MUT{env: [%{"name" => "FOO", "value" => "bar"}], add_parent_env: false}
      pod_manifest = MUT.manifest(parent_pod_manifest, template_opts, make_ref())

      assert get_in(pod_manifest, env_var_access("RELEASE_NODE")) == []
      assert get_in(pod_manifest, env_var_access("FOO")) == ["bar"]
    end
  end

  describe "manifest/2 with nil as template opts" do
    test "Uses parent pod's values for empty template opts", %{
      parent_pod_manifest_full: parent_pod_manifest
    } do
      pod_manifest = MUT.manifest(parent_pod_manifest, nil, make_ref())

      assert get_in(pod_manifest, app_container_access(~w(resources requests memory))) == "100Mi"

      assert get_in(pod_manifest, env_var_access("RELEASE_NODE")) == ["flame_test@$(POD_IP)"]
    end
  end
end
