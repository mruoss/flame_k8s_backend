defmodule FLAMEK8sBackend.TestSupport.Pods do
  import YamlElixir.Sigil

  @parent_pod_manifest_full ~y"""
  apiVersion: v1
  kind: Pod
  metadata:
    creationTimestamp: "2023-12-13T13:44:24Z"
    generateName: flame-cb76858b7-
    labels:
      app: flame
      excluster: flame
      pod-template-hash: cb76858b7
    name: flame-cb76858b7-ms8nd
    namespace: test-namespace
    ownerReferences:
    - apiVersion: apps/v1
      blockOwnerDeletion: true
      controller: true
      kind: ReplicaSet
      name: flame-cb76858b7
      uid: 403094a3-f852-45cf-bd13-e92e98748b18
    resourceVersion: "179501"
    uid: 02d47d15-c6ac-475d-9c94-7bf8f40835c7
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
      - name: POD_IP
        valueFrom:
          fieldRef:
            apiVersion: v1
            fieldPath: status.podIP
      - name: RELEASE_DISTRIBUTION
        value: name
      - name: RELEASE_NODE
        value: flame_test@$(POD_IP)
      envFrom:
      - configMapRef:
          name: some-config-map
      image: flame-test-image:0.1.0
      imagePullPolicy: IfNotPresent
      name: flame
      resources:
        requests:
          cpu: 100m
          memory: 100Mi
      terminationMessagePath: /dev/termination-log
      terminationMessagePolicy: File
      volumeMounts:
      - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
        name: kube-api-access-smcb8
        readOnly: true
    - name: other-container
      image: other-image:0.1.0
    dnsPolicy: ClusterFirst
    enableServiceLinks: true
    nodeName: flame-test-control-plane
    preemptionPolicy: PreemptLowerPriority
    priority: 0
    restartPolicy: Always
    schedulerName: default-scheduler
    securityContext: {}
    serviceAccount: flame-test
    serviceAccountName: flame-test
    terminationGracePeriodSeconds: 30
    tolerations:
    - effect: NoExecute
      key: node.kubernetes.io/not-ready
      operator: Exists
      tolerationSeconds: 300
    - effect: NoExecute
      key: node.kubernetes.io/unreachable
      operator: Exists
      tolerationSeconds: 300
    volumes:
    - name: kube-api-access-smcb8
      projected:
        defaultMode: 420
        sources:
        - serviceAccountToken:
            expirationSeconds: 3607
            path: token
        - configMap:
            items:
            - key: ca.crt
              path: ca.crt
            name: kube-root-ca.crt
        - downwardAPI:
            items:
            - fieldRef:
                apiVersion: v1
                fieldPath: metadata.namespace
              path: namespace
  status:
    conditions:
    - lastProbeTime: null
      lastTransitionTime: "2023-12-13T13:44:24Z"
      status: "True"
      type: Initialized
    - lastProbeTime: null
      lastTransitionTime: "2023-12-13T13:44:26Z"
      status: "True"
      type: Ready
    - lastProbeTime: null
      lastTransitionTime: "2023-12-13T13:44:26Z"
      status: "True"
      type: ContainersReady
    - lastProbeTime: null
      lastTransitionTime: "2023-12-13T13:44:24Z"
      status: "True"
      type: PodScheduled
    containerStatuses:
    - containerID: containerd://ebb77cb2e138daf21613342ab9553d6544a5fad793380de5f6b853581dce5a9c
      image: docker.io/library/flame-test:0.2.0
      imageID: docker.io/library/import-2023-12-12@sha256:1cdc989cd206ba27a9faa605d6898837d2b477df05a67826a8ce7d7e50517c8f
      lastState: {}
      name: flame
      ready: true
      restartCount: 0
      started: true
      state:
        running:
          startedAt: "2023-12-13T13:44:25Z"
    hostIP: 172.19.0.2
    phase: Running
    podIP: 10.244.0.21
    podIPs:
    - ip: 10.244.0.21
    qosClass: Burstable
    startTime: "2023-12-13T13:44:24Z"
  """

  def parent_pod_manifest_full(), do: @parent_pod_manifest_full
end
