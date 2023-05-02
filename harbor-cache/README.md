**karpenter + bottlerocket + harbor**

use case: 
karpenter will provision a bottlerocket node with userdata , that will configure a mirror registry to harbor ,
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
    endpoint = ["http://<name of the harbor-core svc>.<namespace>.svc.cluster.local/v2/<name of the proxy project in harbor>"] #you can name ot what ever you want i chose to it quay.io


    [[settings.container-registry.mirrors]]
    registry = "docker.io"
    endpoint = ["http://<name of the core harbor-svc>.<namespace>.svc.cluster.local/v2/<name of the proxy project in harbor>"]

    [[settings.container-registry.credentials]]
    registry = "<name of the core svc>.<namespace>.svc.cluster.local"
    auth = "username:password in base64" #user that has the right permissions in harbor


    [settings.network]
    hosts = [
      ["10.100.151.4", ["<name of the core svc>.<namespace>.svc.cluster.local"]]
    ] 
 ```
you need to add `[settings.network]` to resolve the name of the service to its ip. (yes if the service is deleted or changed you will have to change the ip manually here. but bacause this is only for proxy cache its not that critical. *and* you can change create the service whit an ip of your choice - if its available and in the ip range of your cluster. 

with those configurations the mirror will look like:
``docker.io/bitnami/elasticsearch:latest  >  <core svc>.<namespace>.svc.cluster.local/<proxy project>/bitnami/elasticsearch:latest``

**Harbor configuration**

first you need to create a registry endpoint:

![image](https://user-images.githubusercontent.com/126203742/235632247-521090aa-03fb-436a-9830-614bf8fad92d.png)

test the connection. add a username and password if its a private registry. 

then create the proxy cache project:

![image](https://user-images.githubusercontent.com/126203742/235632878-4551301b-0faa-47f5-b678-ca3ae2b5e83e.png)

thats it ! good luck!




