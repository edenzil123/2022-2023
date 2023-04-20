**karpenter + bottlerocket + harbor**

use case: 
karpenter will provision a bottlerocket node with userdata , that will configure the mirror registry to harbor ,
*and* containerd will use the private kubernetes network.

**awsnodetemplate.yaml**
```yaml
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: test-amd
spec:
  amiFamily: Bottlerocket
  userData: |
    [[settings.container-registry.mirrors]]
    registry = "quay.io"
    endpoint = ["http://<name of the core svc>.<namespace>.svc.cluster.local/v2/<name of the proxy project in harbor>"]


    [[settings.container-registry.mirrors]]
    registry = "docker.io"
    endpoint = ["http://<name of the core svc>.<namespace>.svc.cluster.local/v2/<name of the proxy project in harbor>"]

    [[settings.container-registry.credentials]]
    registry = "<name of the core svc>.<namespace>.svc.cluster.local"
    auth = "username:password in base64"


    [settings.network]
    hosts = [
      ["10.100.151.4", ["registry-cache-harbor-core.node-management.svc.cluster.local"]]
    ] # you need to add a 
 ```
