## Instalación de Kubernetes con Kubespray + Ansible

### `inventory.ini`

```yaml
[all]
debian-nodo1 ansible_host=100.126.156.35 ip=100.126.156.35 access_ip=100.126.156.35 ansible_user=usuario1
debian-nodo2 ansible_host=100.78.239.126 ip=100.78.239.126 access_ip=100.78.239.126 ansible_user=usuario1
debian-nodo3 ansible_host=100.115.184.93 ip=100.115.184.93 access_ip=100.115.184.93 ansible_user=usuario1
debian-nodo4 ansible_host=100.87.128.22 ip=100.87.128.22 access_ip=100.87.128.22 ansible_user=usuario1
debian-nodo5 ansible_host=100.108.88.7 ip=100.108.88.7 access_ip=100.108.88.7 ansible_user=usuario1
debian-nodo6 ansible_host=100.111.213.98 ip=100.111.213.98 access_ip=100.111.213.98 ansible_user=usuario1
debian-nodo7 ansible_host=100.126.143.93 ip=100.126.143.93 access_ip=100.126.143.93 ansible_user=usuario1

[kube_control_plane]
debian-nodo5
debian-nodo6
debian-nodo7

[etcd:children]
kube_control_plane

[kube_node]
debian-nodo1
debian-nodo2
debian-nodo3
debian-nodo4

[k8s_cluster:children]
kube_control_plane
kube_node
```