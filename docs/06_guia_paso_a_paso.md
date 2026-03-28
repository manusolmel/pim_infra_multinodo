# 06 — Guía paso a paso de despliegue

Esta guía recoge la secuencia exacta para llegar desde VMs vacías hasta un clúster Kubernetes funcional. Cada paso indica el nodo desde el que se ejecuta.

---

## Fase 1 — Instalación base (en cada VM)

- [ ] **1.1** Crear VM en VirtualBox (4 GB RAM, 2 vCPU, disco dinámico)
- [ ] **1.2** Instalar Debian 13.3 netinst (español, Europe/Madrid, sin entorno gráfico, SSH server + herramientas básicas)
- [ ] **1.3** Crear usuario `usuario1`, añadir a sudoers
- [ ] **1.4** Instalar curl: `sudo apt update && sudo apt install -y curl`
- [ ] **1.5** Instalar Tailscale: `curl -fsSL https://tailscale.com/install.sh | sh`
- [ ] **1.6** Unir a la tailnet: `sudo tailscale up` → abrir enlace en navegador
- [ ] **1.7** Anotar la IP Tailscale: `tailscale ip -4`

**Repetir los pasos 1.1–1.7 para las 8 máquinas** (1 admin + 3 CP + 4 workers).

---

## Fase 2 — Configuración de Tailscale (consola web)

- [ ] **2.1** Ir a `login.tailscale.com/admin/dns`
- [ ] **2.2** Añadir DNS de respaldo: 8.8.8.8, 1.1.1.1, 9.9.9.9
- [ ] **2.3** Verificar que "Override DNS servers" está **desactivado**

---

## Fase 3 — Preparación del nodo admin (`debian-admin`)

- [ ] **3.1** Instalar paquetes base:
  ```bash
  sudo apt install -y git python3 python3-venv python3-pip ssh curl rsync
  ```

- [ ] **3.2** Generar clave SSH:
  ```bash
  ssh-keygen -t ed25519 -C "admin-kubespray"
  ```

- [ ] **3.3** Copiar clave a cada nodo (×7):
  ```bash
  ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@<IP_TAILSCALE>
  ```

- [ ] **3.4** Clonar Kubespray:
  ```bash
  cd ~
  git clone https://github.com/kubernetes-sigs/kubespray.git
  cd kubespray
  ```

- [ ] **3.5** Crear entorno virtual e instalar dependencias:
  ```bash
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -U pip
  pip install -r requirements.txt
  ```

- [ ] **3.6** Clonar el repositorio del proyecto:
  ```bash
  cd ~
  git clone git@github.com:manusolmel/pim_infra_multinodo.git
  ```

---

## Fase 4 — Preparación de los nodos del clúster (desde `debian-admin`)

Activar el entorno siempre:
```bash
cd ~/kubespray && source .venv/bin/activate
```

Variable de inventario (para copiar/pegar):
```bash
INV=~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini
```

- [ ] **4.1** Verificar conectividad:
  ```bash
  ansible -i $INV all -m ping -b
  ```

- [ ] **4.2** Instalar paquetes necesarios:
  ```bash
  ansible -i $INV all \
    -m apt -a "name=rsync,apt-transport-https,gnupg2,ca-certificates state=present update_cache=yes" -b
  ```

- [ ] **4.3** Configurar sudo sin contraseña:
  ```bash
  ansible -i $INV all \
    -m copy -a "content='usuario1 ALL=(ALL) NOPASSWD:ALL' dest=/etc/sudoers.d/usuario1 mode=0440" -b
  ```

- [ ] **4.4** Asegurar hostname en `/etc/hosts`:
  ```bash
  ansible -i $INV all \
    -m shell -a "hostname | xargs -I{} grep -q {} /etc/hosts || hostname | xargs -I{} sh -c 'echo 127.0.1.1 {} >> /etc/hosts'" -b
  ```

- [ ] **4.5** Sincronizar relojes:
  ```bash
  ansible -i $INV all \
    -m shell -a "chronyc makestep && sleep 2 && date" -b
  ```

---

## Fase 5 — Configuración del inventario

Verificar que estos ficheros existen y contienen la configuración correcta en `~/pim_infra_multinodo/kubespray/inventory/lab/`:

- [ ] **5.1** `inventory.ini` — nodos, IPs, grupos
- [ ] **5.2** `group_vars/all/all.yml` — `allow_unsupported_distribution_setup`, `ntp_package: chrony`
- [ ] **5.3** `group_vars/all/download.yml` — `download_run_once: true`
- [ ] **5.4** `group_vars/k8s_cluster/k8s-net-calico.yml` — VXLAN, MTU 1230
- [ ] **5.5** `group_vars/k8s_cluster/k8s-cluster.yml` — containerd, IPVS, CoreDNS

Verificar lectura correcta:
```bash
ansible-inventory -i $INV --list | head -30
```

---

## Fase 6 — Despliegue del clúster

- [ ] **6.1** Limpiar residuos de intentos anteriores (si los hay):
  ```bash
  ansible -i $INV all -m shell -a "rm -rf /tmp/releases /tmp/kubespray_cache" -b
  rm -rf /tmp/kubespray_cache
  ```

- [ ] **6.2** Lanzar el despliegue:
  ```bash
  ansible-playbook -i $INV cluster.yml -b \
    2>&1 | tee ~/pim_infra_multinodo/logs/deploy_$(date +%Y%m%d_%H%M%S).log
  ```

  Tiempo estimado: ~25 minutos.

---

## Fase 7 — Post-despliegue

- [ ] **7.1** Configurar kubectl:
  ```bash
  mkdir -p ~/.kube
  cp ~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/admin.conf ~/.kube/config
  export PATH=$PATH:~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/
  ```

- [ ] **7.2** Verificar nodos:
  ```bash
  kubectl get nodes
  ```
  Esperado: 7 nodos en estado `Ready`.

- [ ] **7.3** Verificar pods del sistema:
  ```bash
  kubectl get pods -A
  ```
  Esperado: todos los pods en estado `Running`.

- [ ] **7.4** Prueba funcional:
  ```bash
  kubectl create deployment nginx --image=nginx
  kubectl scale deployment nginx --replicas=4
  kubectl get pods -o wide
  ```
  Esperado: 4 réplicas, una por worker.

- [ ] **7.5** Limpieza de la prueba:
  ```bash
  kubectl delete deployment nginx
  ```

---

## Fase 8 — Si algo falla

### El playbook falla a mitad de ejecución

1. Leer el error y corregir la causa (ver doc `03_despliegue_kubespray.md`, sección 5).
2. Relanzar `cluster.yml` (es idempotente).
3. Si el estado es inconsistente, hacer reset completo y redesplegar:
   ```bash
   ansible-playbook -i $INV reset.yml -b -e reset_confirmation=yes
   ansible -i $INV all -m shell -a "rm -rf /tmp/releases /tmp/kubespray_cache" -b
   # Corregir la causa del fallo y volver a la Fase 6
   ```

### Errores de certificados TLS

Sincronizar relojes en todos los nodos:
```bash
ansible -i $INV all -m shell -a "chronyc makestep && sleep 2 && date" -b
```

### Nodos en `NotReady` sin pods de Calico

Reset completo y redespliegue limpio. No intentar instalar Calico manualmente.

---

## Checklist resumen

```
□ 8 VMs con Debian 13 + Tailscale
□ DNS de respaldo en consola Tailscale
□ Admin: git, python3, venv, pip, ssh, curl, rsync
□ Admin: clave SSH copiada a los 7 nodos
□ Admin: Kubespray clonado + venv + dependencias
□ Admin: repo del proyecto clonado
□ Nodos: rsync, apt-transport-https, gnupg2, ca-certificates
□ Nodos: NOPASSWD sudo
□ Nodos: hostname en /etc/hosts
□ Nodos: chrony sincronizado
□ Inventario: 5 ficheros verificados
□ Despliegue: cluster.yml ejecutado sin errores
□ Post: kubectl configurado
□ Post: 7 nodos Ready
□ Post: pods del sistema Running
□ Post: prueba funcional nginx ×4
```
