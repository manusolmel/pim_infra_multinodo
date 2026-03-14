### venv para Ansible

```shell
cd ~/kubespray
source .venv/bin/activate
```

### Forzar sincronización horaria en TODOS los nodos

```shell
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m shell -a "chronyc makestep && sleep 2 && date" -b
```
### Reset completo

```shell
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini \
  reset.yml -b -e reset_confirmation=yes
```

### Limpiar residuos

```shell
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m shell -a "rm -rf /tmp/releases /tmp/kubespray_cache" -b

rm -rf /tmp/kubespray_cache
```

### Despliegue con log

```shell
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini \
  cluster.yml -b \
  2>&1 | tee ~/pim_infra_multinodo/logs/deploy_final_$(date +%Y%m%d_%H%M%S).log
```

### Reiniciar clúster

```shell
# workers primero
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini kube_node \
  -m ansible.builtin.reboot -b

# luego control plane
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini kube_control_plane \
  -m ansible.builtin.reboot -b
```


### Apagar clúster
```shell
# workers primero
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini kube_node \
  -m shell -a "shutdown -h now" -b

# luego control plane
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini kube_control_plane \
  -m shell -a "shutdown -h now" -b
```