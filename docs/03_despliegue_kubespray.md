# 03 — Despliegue del clúster con Kubespray

## 1. Ficheros de configuración

Toda la configuración vive en `~/pim_infra_multinodo/kubespray/inventory/lab/`. Kubespray se mantiene intacto como dependencia externa.

### 1.1 Inventario — `inventory.ini`

```ini
[all]
debian-nodo1 ansible_host=100.126.156.35 ip=100.126.156.35 access_ip=100.126.156.35
debian-nodo2 ansible_host=100.78.239.126 ip=100.78.239.126 access_ip=100.78.239.126
debian-nodo3 ansible_host=100.115.184.93 ip=100.115.184.93 access_ip=100.115.184.93
debian-nodo4 ansible_host=100.87.128.22  ip=100.87.128.22  access_ip=100.87.128.22
debian-nodo5 ansible_host=100.108.88.7   ip=100.108.88.7   access_ip=100.108.88.7
debian-nodo6 ansible_host=100.111.213.98 ip=100.111.213.98 access_ip=100.111.213.98
debian-nodo7 ansible_host=100.126.143.93 ip=100.126.143.93 access_ip=100.126.143.93

[all:vars]
ansible_user=usuario1
ansible_ssh_private_key_file=~/.ssh/id_ed25519

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

Las tres variables por host (`ansible_host`, `ip`, `access_ip`) coinciden porque toda la comunicación pasa por Tailscale.

### 2.2 Variables globales — `all.yml`

```yaml
kubectl_localhost: true
kubeconfig_localhost: true
override_system_hostname: false
allow_unsupported_distribution_setup: true
ntp_enabled: true
ntp_manage_config: true
ntp_servers:
  - "0.es.pool.ntp.org iburst"
  - "1.es.pool.ntp.org iburst"
  - "2.es.pool.ntp.org iburst"
  - "3.es.pool.ntp.org iburst"
ntp_package: chrony
```

| Parámetro                                    | Función                                                    |
| -------------------------------------------- | ---------------------------------------------------------- |
| `kubectl_localhost` / `kubeconfig_localhost` | Trae `kubectl` y `admin.conf` al nodo admin                |
| `allow_unsupported_distribution_setup`       | Debian 13 Trixie no está en la lista oficial de Kubespray  |
| `ntp_package: chrony`                        | Debian 13 eliminó el paquete `ntp`; chrony es el sustituto |
| `ntp_servers` (pool España)                  | Servidores NTP cercanos para menor latencia                |

### 1.3 Descargas — `download.yml`

Kubespray descarga múltiples binarios e imágenes (kubeadm, kubectl, containerd, etc.) necesarios para el despliegue del clúster. Por defecto, cada nodo realiza estas descargas de forma independiente.

En un entorno multinodo como este (7 nodos), esto provoca que todos los nodos descarguen simultáneamente los mismos recursos desde los mismos CDN (GitHub, dl.k8s.io, etc.), lo que puede activar mecanismos de rate-limiting y causar fallos intermitentes en la instalación.

Para evitar este problema, se habilita:

```yaml
download_run_once: true
```

Con esta opción, el flujo cambia:

1. Un único nodo (normalmente el primero del inventario) descarga todos los binarios.
2. Kubespray utiliza `rsync` para distribuir estos ficheros al resto de nodos a través de la red privada.

> La opción `download_localhost` fue descartada debido a conflictos de permisos durante la distribución de archivos. Los binarios se descargaban en la máquina de administración y se copiaban a los nodos mediante `rsync`, pero el directorio de destino (`/tmp/releases/`) era creado por Ansible con privilegios de root, mientras que la copia se realizaba como usuario no privilegiado. Esta discrepancia provocaba errores de permisos (`Permission denied`), por lo que se optó por `download_run_once`, que mantiene coherencia en el modelo de ejecución y evita estos problemas.

### 1.4 Red Calico — `k8s-net-calico.yml`

```yaml
calico_network_backend: vxlan
calico_ipip_mode: 'Never'
calico_vxlan_mode: 'Always'
calico_veth_mtu: 1230
```

Este fichero es crítico porque define cómo se implementa la red de pods entre nodos.

#### Contexto

El clúster utiliza **Tailscale** para interconectar los nodos. Tailscale encapsula el tráfico en túneles **WireGuard** (protocolo VPN), lo que reduce el **MTU efectivo** (Maximum Transmision Unit) de la red a aproximadamente **1280 bytes**.

Esto implica que la red de pods de Kubernetes no puede mantener el MTU habitual de 1500 bytes, ya que cualquier mecanismo overlay de Calico añadirá cabeceras extra y podría hacer que los paquetes superen el límite real del enlace.

#### Decisión adoptada

Se eligió **VXLAN (Virtual eXtensible LAN)** porque permite a **Calico** crear una red virtual entre nodos sobre **Tailscale/WireGuard**, sin depender de **BGP (Border Gateway Protocol)** para intercambiar rutas de pods.

Además, se desactiva explícitamente **IPIP (IP-in-IP)** para evitar tener dos mecanismos de encapsulación posibles y asegurar un comportamiento de red consistente y predecible.

- `calico_network_backend: vxlan` → selecciona VXLAN como backend de red
- `calico_ipip_mode: 'Never'` → desactiva IPIP
- `calico_vxlan_mode: 'Always'` → fuerza el uso de VXLAN entre nodos

#### Ajuste del MTU

VXLAN añade aproximadamente **50 bytes de cabecera**. Como Tailscale deja un MTU efectivo cercano a **1280 bytes**, se reduce el MTU de las interfaces virtuales de los pods a:
```yaml
calico_veth_mtu: 1230
```

1280 (MTU efectivo de Tailscale) - 50 (cabecera VXLAN) = 1230

De este modo, los paquetes generados por los pods siguen cabiendo dentro del límite real del enlace una vez encapsulados por Calico.

#### Flujo de red resultante

```
Pod (1230)
  ↓
+ VXLAN (~50)
  ↓
≈ 1280 (límite Tailscale)
  ↓
WireGuard (Tailscale)
  ↓
Red → Nodo destino → Desencapsulado → Pod
```

##### Resultado
- Comunicación estable entre pods en distintos nodos
- Evitación de fragmentación y pérdidas silenciosas de paquetes
- Funcionamiento predecible de la red del clúster en un entorno con túneles WireGuard

### 1.5 Clúster — `k8s-cluster.yml`

```yaml
kube_network_plugin: calico
kube_service_addresses: 10.233.0.0/18
kube_pods_subnet: 10.233.64.0/18
kube_network_node_prefix: 24
container_manager: containerd
kube_proxy_mode: ipvs
cluster_name: cluster.local
dns_mode: coredns
enable_nodelocaldns: true
nodelocaldns_ip: 169.254.25.10
resolvconf_mode: host_resolvconf
```

| Parámetro | Elección | Razón |
|-----------|----------|-------|
| `kube_network_plugin` | calico | Se selecciona Calico como CNI (Container Network Interface), encargado de proporcionar conectividad entre pods y aplicar la red overlay del clúster. |
| `kube_service_addresses` | 10.233.0.0/18 | Define el rango de IPs virtuales para los Services de Kubernetes. Se elige una subred privada separada para evitar solapamientos con la red de pods y con la red de Tailscale. |
| `kube_pods_subnet` | 10.233.64.0/18 | Define el rango de IPs asignadas a los pods. Se separa del rango de Services para mantener claridad de direccionamiento y evitar conflictos. |
| `kube_network_node_prefix` | 24 | Asigna a cada nodo un bloque `/24` dentro de la red de pods, permitiendo distribuir direcciones por nodo de forma ordenada. |
| `container_manager` | containerd | Runtime de contenedores estándar desde la deprecación de dockershim en Kubernetes v1.24. |
| `kube_proxy_mode` | ipvs | Mejor rendimiento y escalabilidad que iptables cuando aumenta el número de Services y endpoints. |
| `cluster_name` | cluster.local | Dominio DNS interno del clúster, utilizado para la resolución de nombres de Services y componentes internos. |
| `dns_mode` | coredns | CoreDNS es el servicio DNS interno estándar de Kubernetes para resolver nombres dentro del clúster. |
| `enable_nodelocaldns` | true | Activa una caché DNS local en cada nodo, reduciendo latencia y carga sobre CoreDNS. |
| `nodelocaldns_ip` | 169.254.25.10 | IP local reservada para la caché DNS de nodo, utilizada por nodelocaldns como punto de resolución cercano al host. |
| `resolvconf_mode` | host_resolvconf | Hace que Kubernetes tome como referencia el `/etc/resolv.conf` del host, que en este laboratorio está gestionado por Tailscale. |



---

## 2. Ejecución del despliegue

### 2.1 Ejecución del playbook de despliegue

Este comando ejecuta el despliegue completo del clúster Kubernetes con **Kubespray**, utilizando el inventario y las variables definidas en el repositorio del proyecto. La ejecución se realiza con privilegios elevados y su salida se muestra en pantalla y se guarda simultáneamente en un fichero de log con marca temporal para facilitar su revisión posterior.

```bash
# Abrimos repositorio de kubespray
cd ~/kubespray
# Ejecutamos el entorno virtual para ejecutar ansible
source .venv/bin/activate

# Lanzamos el playbook de despliegue
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini \
  cluster.yml -b \
  2>&1 | tee ~/pim_infra_multinodo/logs/deploy_$(date +%Y%m%d_%H%M%S).log
```

### 2.2 Fases del playbook `cluster.yml`

1. Validación del inventario y compatibilidad del entorno
2. Bootstrap de nodos (paquetes, chrony, sysctl, ip_forwarding)
3. Descarga de binarios e imágenes (containerd, runc, crictl, kubeadm, kubectl, imágenes de sistema)
4. Instalación de containerd
5. Despliegue de etcd (3 nodos, certificados TLS)
6. Inicialización del plano de control (kubeadm init + join)
7. Unión de workers al clúster
8. Despliegue de Calico (CNI con VXLAN)
9. Despliegue de CoreDNS + nodelocaldns
10. Generación y copia de artefactos de administración (`admin.conf`, `kubectl.sh`)

### 2.3 Resultado del despliegue

| Nodo | ok | changed | failed | skipped |
|------|-----|---------|--------|---------|
| debian-nodo1 | 485 | 108 | 0 | 401 |
| debian-nodo2 | 472 | 109 | 0 | 396 |
| debian-nodo3 | 472 | 109 | 0 | 396 |
| debian-nodo4 | 472 | 109 | 0 | 396 |
| debian-nodo5 | 782 | 226 | 0 | 672 |
| debian-nodo6 | 578 | 147 | 0 | 653 |
| debian-nodo7 | 580 | 148 | 0 | 651 |

### 2.4 Post-despliegue — configuración de kubectl

```bash
mkdir -p ~/.kube

cp ~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/admin.conf ~/.kube/config

export PATH=$PATH:~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/
```

Tras el despliegue, es necesario configurar `kubectl` en el nodo de administración para poder operar el clúster. Para ello, se copia el fichero `admin.conf` generado por Kubespray a la ruta estándar `~/.kube/config`, que contiene las credenciales y la configuración de acceso al API server. 

Además, se añade al `PATH` el directorio de artefactos generado por Kubespray para poder utilizar directamente el binario `kubectl.sh`.

---

## 3. Verificación del clúster

### 3.1 Nodos
#screenshot
Este comando permite verificar que todos los nodos del clúster se han registrado correctamente y se encuentran en estado `Ready`:

```bash
kubectl get nodes
```

```
NAME           STATUS   ROLES           AGE     VERSION
debian-nodo1   Ready    <none>          6m38s   v1.35.1
debian-nodo2   Ready    <none>          6m38s   v1.35.1
debian-nodo3   Ready    <none>          6m37s   v1.35.1
debian-nodo4   Ready    <none>          6m38s   v1.35.1
debian-nodo5   Ready    control-plane   7m37s   v1.35.1
debian-nodo6   Ready    control-plane   7m14s   v1.35.1
debian-nodo7   Ready    control-plane   6m59s   v1.35.1
```

### 3.2 Pods del sistema

Se comprobó que todos los pods del sistema estaban en estado `Running`.

#screenshot

| Componente                | Instancias | Función                             |
| ------------------------- | ---------: | ----------------------------------- |
| `calico-node`             |          7 | Red de pods en cada nodo            |
| `calico-kube-controllers` |          1 | Control de red Calico               |
| `kube-apiserver`          |          3 | API del clúster                     |
| `kube-controller-manager` |          3 | Controladores internos              |
| `kube-scheduler`          |          3 | Asignación de pods a nodos          |
| `kube-proxy`              |          7 | Gestión de Services                 |
| `coredns`                 |          2 | DNS interno del clúster             |
| `dns-autoscaler`          |          1 | Ajuste automático de CoreDNS        |
| `nodelocaldns`            |          7 | Caché DNS local por nodo            |
| `nginx-proxy`             |          4 | Proxy local de acceso al API server |

### 3.3 Prueba funcional

```bash
kubectl create deployment nginx --image=nginx
kubectl scale deployment nginx --replicas=4
kubectl get pods -o wide
```

```
NAME                     READY   STATUS    NODE            IP
nginx-56c45fd5ff-cdjth   1/1     Running   debian-nodo4    10.233.110.4
nginx-56c45fd5ff-kppwl   1/1     Running   debian-nodo3    10.233.117.129
nginx-56c45fd5ff-npfg8   1/1     Running   debian-nodo2    10.233.66.129
nginx-56c45fd5ff-phlzc   1/1     Running   debian-nodo1    10.233.114.130
```

Las 4 réplicas se distribuyeron una por worker, confirmando que el scheduler, la red CNI y los nodos funcionan correctamente.

---

## 4. Incidencias encontradas y resolución

### 4.1 Debian 13 no soportada

**Síntoma**: el playbook aborta en la validación de distribución.  
**Causa**: Trixie no está en la lista oficial de Kubespray.  
**Solución**: `allow_unsupported_distribution_setup: true`.

### 4.2 Paquete `ntp` inexistente

**Síntoma**: fallo al instalar paquetes de sincronización horaria.  
**Causa**: Debian 13 Debian 13 ya no incluye el paquete `ntp` y se utiliza `chrony` como alternativa.
**Solución**: `ntp_package: chrony`. Se encontró inspeccionando los defaults de Kubespray con `grep -r "ntp_package" ~/kubespray/roles/kubespray_defaults/ --include="*.yml"`.

### 4.3 Rate-limiting en descargas

**Síntoma**: fallos intermitentes al descargar binarios desde `dl.k8s.io` y `github.com`.  
**Causa**: 7 nodos descargando en paralelo desde la misma IP pública.  
**Solución**: `download_run_once: true`.

### 4.4 `rsync` ausente

**Síntoma**: fallo al distribuir binarios con `download_run_once`.  
**Causa**: Debian 13 minimal no incluye `rsync`.  
**Solución**: instalar `rsync` en admin y en todos los nodos antes del despliegue.  
**Conclusión**: `download_run_once` requiere rsync en ambos extremos (origen y destino).

### 4.5 Permisos denegados en `/tmp/releases`

**Síntoma**: `Permission denied` al copiar binarios con rsync.  
**Causa**: `download_localhost: true` ejecutaba rsync como usuario no privilegiado contra un directorio creado como root.  
**Solución**: eliminar `download_localhost: true`, mantener solo `download_run_once: true`. Limpiar residuos con `ansible all -m shell -a "rm -rf /tmp/releases" -b`.

### 4.6 `sudo` no resuelve el hostname

**Síntoma**: `unable to resolve host debian-nodoX`.  
**Causa**: hostname no presente en `/etc/hosts` en Debian 13 minimal.  
**Solución**: añadir `127.0.1.1 <hostname>` en cada nodo.

### 4.7 Fallos DNS transitorios

**Síntoma**: `apt-get update` falla intermitentemente.  
**Causa**: dependencia total del resolver de Tailscale (100.100.100.100).  
**Solución**: configurar DNS de respaldo (8.8.8.8, 1.1.1.1, 9.9.9.9) en la consola de Tailscale.

### 4.8 Desfase horario entre nodos

**Síntoma**: error de certificado TLS: `certificate has expired or is not yet valid`.  
**Causa**: VirtualBox congela el reloj al pausar VMs. `kubeadm` valida certificados antes de que chrony sincronice.  
**Solución**: forzar sincronización con `chronyc makestep` antes de cualquier operación. No pausar VMs.

### 4.9 CNI no desplegado tras fallo parcial

**Síntoma**: todos los nodos en `NotReady`, sin pods de Calico.  
**Causa**: el playbook falló al unir un nodo (por desfase horario). Al relanzar, la espera de nodos `Ready` agotaba reintentos, pero los nodos no podían pasar a `Ready` sin Calico.  
**Intento fallido**: instalar Calico manualmente con el operador Tigera (CRD excedía el límite de 256KB en annotations).  
**Solución definitiva**: reset completo (`reset.yml`) y redespliegue limpio con todos los prerequisitos ya resueltos.  
**Conclusión**: ante un despliegue parcial con componentes críticos faltantes, es preferible un reset limpio que una reparación manual. Kubespray es idempotente pero espera ser el gestor único de todos los componentes.

---

## 5. Resumen de criterios de diseño

| Decisión                  | Alternativas                | Elección                   | Razón                                                                                                                                |
| ------------------------- | --------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Orquestador               | Docker Compose, Swarm, K3s  | Kubernetes (Kubespray)     | Alta disponibilidad nativa, escalado declarativo y alineación con el estándar de la industria                                        |
| Herramienta de despliegue | kubeadm manual, K3s, RKE2   | Kubespray + Ansible        | Automatización completa del despliegue y gestión reproducible del clúster                                                            |
| CNI                       | Flannel, Cilium             | Calico (VXLAN)             | Solución madura, soporte de Network Policies y uso de VXLAN como red overlay                                                         |
| Encapsulación / overlay   | IPIP                        | VXLAN                      | Permite una red overlay entre nodos sin depender de BGP (Border Gateway Protocol) y se ajusta al MTU efectivo impuesto por Tailscale |
| Runtime                   | CRI-O, Docker               | containerd                 | Runtime CRI estándar y ampliamente soportado; Kubernetes eliminó dockershim en la versión 1.24 :contentReference[oaicite:0]{index=0} |
| kube-proxy mode           | iptables                    | IPVS                       | Mejor rendimiento y escalabilidad que iptables cuando aumenta el número de Services                                                  |
| Sincronización horaria    | ntpd, systemd-timesyncd     | chrony                     | Adecuado para entornos virtualizados y compatible con Debian 13                                                                      |
| Red entre nodos           | VLAN, VPN punto a punto     | Tailscale (WireGuard mesh) | IP estable, NAT traversal y cifrado automático                                                                                       |
| Descargas                 | Paralela, localhost + rsync | download_run_once          | Evita rate-limiting de los CDN sin introducir conflictos de permisos                                                                 |