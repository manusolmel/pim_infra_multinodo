# 04 — Referencia de comandos

**Proyecto**: Infraestructura de Hosting Multinodo

---

Todos los comandos de Ansible se ejecutan desde `~/kubespray` con el entorno virtual activo:

```bash
cd ~/kubespray
source .venv/bin/activate
```

La variable `INV` se usa a lo largo de este documento como abreviatura:

```bash
INV=~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini
```

---

## Parte A — Comandos utilizados durante el despliegue

Estos son los comandos ejecutados cronológicamente para poner en marcha el clúster.

### Preparación de nodos

```bash
# Instalar paquetes necesarios en todos los nodos
ansible -i $INV all \
  -m apt -a "name=rsync,apt-transport-https,gnupg2,ca-certificates state=present update_cache=yes" -b

# Configurar sudo sin contraseña (laboratorio)
ansible -i $INV all \
  -m copy -a "content='usuario1 ALL=(ALL) NOPASSWD:ALL' dest=/etc/sudoers.d/usuario1 mode=0440" -b

# Asegurar hostname en /etc/hosts
ansible -i $INV all \
  -m shell -a "hostname | xargs -I{} grep -q {} /etc/hosts || hostname | xargs -I{} sh -c 'echo 127.0.1.1 {} >> /etc/hosts'" -b

# Forzar sincronización horaria
ansible -i $INV all \
  -m shell -a "chronyc makestep && sleep 2 && date" -b
```

### Verificación previa

```bash
# Test de conectividad SSH + sudo
ansible -i $INV all -m ping -b

# Verificar que Ansible lee correctamente las variables
ansible-inventory -i $INV --list | head -30
```

### Despliegue del clúster

```bash
# Despliegue completo con log
ansible-playbook -i $INV cluster.yml -b \
  2>&1 | tee ~/pim_infra_multinodo/logs/deploy_$(date +%Y%m%d_%H%M%S).log
```

### Configuración post-despliegue

```bash
# Copiar kubeconfig
mkdir -p ~/.kube
cp ~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/admin.conf ~/.kube/config

# Añadir kubectl al PATH
export PATH=$PATH:~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/
```

### Limpieza de intentos fallidos

```bash
# Limpiar residuos en todos los nodos
ansible -i $INV all -m shell -a "rm -rf /tmp/releases /tmp/kubespray_cache" -b

# Limpiar en el admin
rm -rf /tmp/kubespray_cache
```

---

## Parte B — Comandos operativos del clúster

Estos son los comandos del día a día para operar y administrar el clúster ya desplegado.

### Verificación

```bash
# Estado de los nodos
kubectl get nodes
kubectl get nodes -o wide

# Pods del sistema
kubectl get pods -A
kubectl get pods -o wide -A

# Conectividad Ansible
ansible -i $INV all -m ping -b

# Sincronización horaria
ansible -i $INV all -m command -a "chronyc tracking" -b
```

### Despliegue de aplicaciones

```bash
# Crear un Deployment
kubectl create deployment nginx --image=nginx

# Escalar réplicas
kubectl scale deployment nginx --replicas=4

# Ver distribución de pods por nodo
kubectl get pods -o wide

# Eliminar un pod (para probar recreación automática)
kubectl delete pod <nombre-del-pod>

# Observar recreación en tiempo real
kubectl get pods -w
```

### Escalado del clúster

```bash
# Añadir workers: primero editar inventory.ini, luego:
ansible-playbook -i $INV facts.yml -b
ansible-playbook -i $INV scale.yml -b

# Eliminar un nodo
ansible-playbook -i $INV remove-node.yml -b -e node=<nombre-del-nodo>
```

### Reset completo

```bash
ansible-playbook -i $INV reset.yml -b -e reset_confirmation=yes
```

### Reinicio ordenado del clúster

```bash
# 1. Workers primero
ansible -i $INV kube_node -m ansible.builtin.reboot -b

# 2. Control plane después
ansible -i $INV kube_control_plane -m ansible.builtin.reboot -b
```

### Apagado ordenado del clúster

```bash
# 1. Workers primero
ansible -i $INV kube_node -m shell -a "shutdown -h now" -b

# 2. Control plane después
ansible -i $INV kube_control_plane -m shell -a "shutdown -h now" -b
```

El orden importa: los workers se apagan primero para que el plano de control mantenga gobierno del clúster mientras se vacía la capacidad de ejecución.

### Forzar sincronización horaria

```bash
ansible -i $INV all -m shell -a "chronyc makestep && sleep 2 && date" -b
```

Ejecutar siempre antes de operar el clúster si las VMs han estado apagadas o pausadas.

---

## Parte C — Referencia rápida (copiar y pegar)

```bash
# === SESIÓN DE TRABAJO ===
cd ~/kubespray && source .venv/bin/activate
INV=~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini

# === VERIFICACIÓN ===
ansible -i $INV all -m ping -b
kubectl get nodes
kubectl get pods -A

# === DESPLIEGUE ===
ansible-playbook -i $INV cluster.yml -b 2>&1 | tee ~/pim_infra_multinodo/logs/deploy_$(date +%Y%m%d_%H%M%S).log

# === ESCALADO ===
ansible-playbook -i $INV scale.yml -b

# === ELIMINACIÓN DE NODO ===
ansible-playbook -i $INV remove-node.yml -b -e node=<nodo>

# === RESET ===
ansible-playbook -i $INV reset.yml -b -e reset_confirmation=yes

# === REINICIO ORDENADO ===
ansible -i $INV kube_node -m ansible.builtin.reboot -b
ansible -i $INV kube_control_plane -m ansible.builtin.reboot -b

# === APAGADO ORDENADO ===
ansible -i $INV kube_node -m shell -a "shutdown -h now" -b
ansible -i $INV kube_control_plane -m shell -a "shutdown -h now" -b

# === SINCRONIZACIÓN HORARIA ===
ansible -i $INV all -m shell -a "chronyc makestep && sleep 2 && date" -b
```
