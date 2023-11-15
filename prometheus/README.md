

##  make prometheus to scrape node labels > makes kube-state-metrics to collect node labels 

in the chart kube-prometheus-stack there is a sub chart named : kube-prometheus-stack/charts/kube-state-metrics, 
if you look at the values.yaml file of kube-state-metrics you will see the  metricLabelsAllowlist argument. 
with him you can set the container to scrape pod, node and namespaces labels. by default it takes none.

so for best practice add this block to the main values.yaml:

```yaml
kube-state-metrics:
  metricLabelsAllowlist: 
     - nodes=[*]
```

you can also define specific labels to scrape and not all with * like i did.



## make node-exporter to add a label of the nodename and node > with relabeling.

add to the main values.yaml the next block:
```yaml
prometheus-node-exporter:
  prometheus:
    monitor:
      relabelings: 
      - sourceLabels: [__meta_kubernetes_pod_node_name]
        separator: ;
        regex: ^(.*)$
        targetLabel: nodename
        replacement: $1
        action: replace
      - sourceLabels: [__meta_kubernetes_pod_node_name]
        separator: ;
        regex: ^(.*)$
        targetLabel: node
        replacement: $1
        action: replace
```
after that you can join metrics from node-exporter and kube-state-metrics like so:
```promql
sum (node_memory_MemAvailable_bytes/1024/1024/1024 * on(node)  group_left(<label from kube_node_labels>) kube_node_labels) by (<label from kube_node_labels>)
```
```promql
sum (node_memory_MemAvailable_bytes/1024/1024/1024 * on(node)  group_left(label_karpenter_sh_provisioner_name, label_eks_amazonaws_com_nodegroup) kube_node_labels) by (label_karpenter_sh_provisioner_name, label_eks_amazonaws_com_nodegroup) 
```
