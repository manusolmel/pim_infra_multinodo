# Despliegue del Clúster Kubernetes con Kubespray

**Proyecto**: Infraestructura de Hosting Multinodo  
**Módulo**: Proyecto de Fin de Ciclo — ASIR  
**Autor principal de la implementación**: Manuel Soler Melero  
**Repositorio**: [github.com/manusolmel/pim_infra_multinodo](https://github.com/manusolmel/pim_infra_multinodo)  
**Fecha**: Marzo 2026  

---

## Índice

1. [Contexto y justificación del cambio de arquitectura](#1-contexto-y-justificación-del-cambio-de-arquitectura)
2. [Arquitectura del laboratorio](#2-arquitectura-del-laboratorio)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [Preparación de los nodos](#4-preparación-de-los-nodos)
5. [Configuración de la red con Tailscale](#5-configuración-de-la-red-con-tailscale)
6. [Ficheros de configuración de Kubespray](#6-ficheros-de-configuración-de-kubespray)
7. [Proceso de instalación paso a paso](#7-proceso-de-instalación-paso-a-paso)
8. [Incidencias encontradas y resolución](#8-incidencias-encontradas-y-resolución)
9. [Verificación del clúster](#9-verificación-del-clúster)
10. [Escalabilidad del clúster](#10-escalabilidad-del-clúster)
11. [Consideraciones de seguridad: laboratorio vs. producción](#11-consideraciones-de-seguridad-laboratorio-vs-producción)
12. [Resumen de decisiones técnicas](#12-resumen-de-decisiones-técnicas)

---

## 1. Contexto y justificación del cambio de arquitectura

### 1.1 Propuesta original (PIM1–PIM3)

En las entregas anteriores del proyecto (PIM1, PIM2 y PIM3), la arquitectura propuesta para la infraestructura de hosting multinodo se basaba en:

- **Orquestación**: Docker + Docker Compose para el despliegue de contenedores.
- **Proxy inverso**: Nginx como reverse proxy con TLS automático vía Let's Encrypt.
- **Base de datos**: MariaDB en replicación master-master (PIM1) y posteriormente PostgreSQL (PIM3).
- **Red privada**: Tailscale (WireGuard) para la interconexión segura entre nodos geográficamente distribuidos.
- **Monitorización**: Prometheus + Grafana + Alertmanager + Loki.
- **Backups**: Política 3-2-1 con Restic/BorgBackup.

Esta arquitectura fue diseñada como una solución funcional y económica orientada a PYMEs, apoyándose exclusivamente en software de código abierto y cumpliendo con la soberanía de datos dentro de la UE.

### 1.2 Motivación del cambio a Kubernetes

Durante el período de prácticas en la empresa Libnamic, se tuvo contacto directo con Kubernetes en un entorno de producción real. Esta experiencia reveló que, para un servicio de hosting multinodo con objetivos de alta disponibilidad, la plataforma de orquestación estándar en la industria es Kubernetes, no Docker Compose.

Las razones técnicas que motivaron el pivote fueron:

- **Alta disponibilidad nativa**: Kubernetes gestiona automáticamente la distribución de réplicas de pods entre nodos. Si un nodo falla, el scheduler reprograma las cargas de trabajo en nodos disponibles sin intervención manual.
- **Almacenamiento persistente y replicable**: A través de PersistentVolumes (PV) y PersistentVolumeClaims (PVC), Kubernetes abstrae el almacenamiento del ciclo de vida del contenedor, permitiendo migración y replicación de datos.
- **Escalabilidad declarativa**: Escalar un servicio es tan sencillo como modificar el campo `replicas` de un Deployment. Kubernetes se encarga de crear o destruir pods para alcanzar el estado deseado.
- **Balanceo de carga integrado**: Los Services de Kubernetes distribuyen el tráfico entre los pods de un Deployment de forma automática, con soporte para diferentes modos (ClusterIP, NodePort, LoadBalancer).
- **Despliegue declarativo**: Toda la infraestructura y los servicios se definen como manifiestos YAML, lo que permite control de versiones, reproducibilidad y auditoría de cambios.

### 1.3 Elección de Kubespray como herramienta de despliegue

Se eligió Kubespray frente a otras alternativas (kubeadm manual, k3s, RKE2) por las siguientes razones:

- **Automatización completa con Ansible**: Kubespray automatiza todo el ciclo de vida del clúster (instalación, escalado, eliminación de nodos) mediante playbooks de Ansible, lo cual es coherente con un perfil DevOps.
- **Producción-ready**: A diferencia de k3s (orientado a edge/IoT), Kubespray despliega un clúster Kubernetes completo y listo para producción.
- **Flexibilidad de configuración**: Permite elegir el CNI (Calico, Flannel, Cilium), el runtime de contenedores (containerd, CRI-O), el proxy mode (iptables, ipvs) y decenas de parámetros más.
- **Separación herramienta/configuración**: Kubespray se clona como un repositorio independiente y toda la configuración del clúster vive en un inventario externo, lo que permite mantener la herramienta intacta y versionar solo la configuración propia.

---

## 2. Arquitectura del laboratorio

### 2.1 Topología del clúster

El laboratorio se compone de **8 máquinas virtuales** ejecutándose sobre VirtualBox, interconectadas a través de una red privada Tailscale (WireGuard):

| Máquina | Hostname | IP Tailscale | Rol | RAM | CPU |
|---------|----------|-------------|-----|-----|-----|
| Admin | debian-admin | 100.109.133.56 | Gestión (Ansible/Kubespray) | 4 GB | 2 |
| Worker 1 | debian-nodo1 | 100.126.156.35 | Worker (kube_node) | 4 GB | 2 |
| Worker 2 | debian-nodo2 | 100.78.239.126 | Worker (kube_node) | 4 GB | 2 |
| Worker 3 | debian-nodo3 | 100.115.184.93 | Worker (kube_node) | 4 GB | 2 |
| Worker 4 | debian-nodo4 | 100.87.128.22 | Worker (kube_node) | 4 GB | 2 |
| Control Plane 1 | debian-nodo5 | 100.108.88.7 | Control-plane + etcd | 4 GB | 2 |
| Control Plane 2 | debian-nodo6 | 100.111.213.98 | Control-plane + etcd | 4 GB | 2 |
| Control Plane 3 | debian-nodo7 | 100.126.143.93 | Control-plane + etcd | 4 GB | 2 |

### 2.2 Justificación de la topología

- **3 nodos control-plane con etcd colocado**: El número impar (3) garantiza el quórum de etcd con tolerancia a la pérdida de 1 nodo. Colocar etcd en los mismos nodos del plano de control simplifica la topología del laboratorio sin sacrificar funcionalidad.
- **4 nodos worker**: Proporcionan capacidad suficiente para demostrar la distribución real de pods entre múltiples nodos durante la defensa.
- **1 nodo de gestión externo al clúster**: La máquina que ejecuta Ansible y Kubespray no forma parte del clúster de Kubernetes. Esto es una buena práctica porque mantiene la herramienta de despliegue aislada del sistema desplegado.

### 2.3 Diagrama de red

```
                    ┌─────────────────────────────────────┐
                    │          Tailscale Tailnet           │
                    │     (VPN mesh WireGuard cifrada)     │
                    └──┬──────┬──────┬──────┬──────┬──────┘
                       │      │      │      │      │
              ┌────────┴──┐ ┌─┴────┐ │   ┌──┴───┐ ┌┴───────┐
              │debian-admin│ │nodo5 │ │   │nodo6 │ │nodo7   │
              │  Ansible   │ │ CP+  │ │   │ CP+  │ │ CP+    │
              │  Kubespray │ │ etcd │ │   │ etcd │ │ etcd   │
              └────────────┘ └──────┘ │   └──────┘ └────────┘
                                      │
                    ┌─────────┬───────┼──────┬─────────┐
                    │         │       │      │         │
                 ┌──┴───┐ ┌──┴───┐ ┌─┴────┐ ┌┴───────┐
                 │nodo1  │ │nodo2 │ │nodo3 │ │nodo4   │
                 │Worker │ │Worker│ │Worker│ │Worker  │
                 └───────┘ └──────┘ └──────┘ └────────┘
```

### 2.4 Componentes del clúster

- **Kubernetes v1.35.1**: Versión del clúster desplegada por Kubespray.
- **containerd**: Runtime de contenedores (sustituto estándar de Docker en Kubernetes desde v1.24).
- **Calico**: Plugin CNI (Container Network Interface) para la red de pods, configurado con VXLAN.
- **CoreDNS**: Servidor DNS interno del clúster para la resolución de nombres de servicios.
- **nodelocaldns**: Caché DNS local en cada nodo para reducir latencia en resolución.
- **kube-proxy (IPVS)**: Proxy de red para los Services de Kubernetes, usando IPVS para mayor rendimiento.
- **nginx-proxy**: Proxy de alta disponibilidad del API server en los nodos worker.
- **chrony**: Servicio de sincronización horaria (NTP) en todos los nodos.

---

## 3. Estructura del repositorio

El repositorio `pim_infra_multinodo` contiene exclusivamente la configuración del proyecto. Kubespray se clona como un repositorio separado y no se modifica.

```
~/pim_infra_multinodo/                    ← Repositorio del proyecto (git)
├── README.md                             ← Descripción general
├── doc_debian13.md                       ← Documentación de instalación del SO
├── docs/                                 ← Documentación formal del proyecto
├── kubespray/
│   └── inventory/
│       └── lab/
│           ├── inventory.ini             ← Inventario de nodos
│           └── group_vars/
│               ├── all/
│               │   ├── all.yml           ← Variables globales
│               │   └── download.yml      ← Configuración de descargas
│               └── k8s_cluster/
│                   ├── k8s-cluster.yml   ← Configuración del clúster
│                   └── k8s-net-calico.yml ← Configuración de la red CNI
├── logs/                                 ← Logs de despliegue (excluidos de git)
└── .gitignore                            ← Excluye *.log

~/kubespray/                              ← Repositorio de Kubespray (no se toca)
├── cluster.yml                           ← Playbook de instalación
├── scale.yml                             ← Playbook de escalado
├── reset.yml                             ← Playbook de limpieza
├── remove-node.yml                       ← Playbook de eliminación de nodos
├── ansible.cfg                           ← Configuración de Ansible
├── requirements.txt                      ← Dependencias Python
└── roles/                                ← Roles de Ansible
```

### 3.1 Principio de separación

Esta estructura sigue el principio de separación entre herramienta y configuración:

- **Kubespray** se mantiene como una dependencia externa intacta, actualizable en cualquier momento con `git pull`.
- **La configuración del clúster** vive en el repositorio del proyecto, versionada con Git.
- **Los playbooks se ejecutan** desde el directorio de Kubespray, apuntando al inventario del repositorio del proyecto con el flag `-i`.

Ejemplo de ejecución:

```bash
cd ~/kubespray
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini cluster.yml -b
```

---

## 4. Preparación de los nodos

### 4.1 Sistema operativo base

Todas las máquinas virtuales se instalaron con **Debian 13.3.0 (Trixie) amd64**, versión netinst, con la siguiente configuración común:

- **Idioma**: Español
- **País/Región**: España
- **Zona horaria**: Europe/Madrid
- **Teclado**: Español
- **Usuario**: `usuario1`, añadido manualmente al grupo de sudoers
- **Paquetes seleccionados en la instalación**: SSH server y herramientas básicas del sistema
- **Sin entorno gráfico** (instalación mínima de servidor)

### 4.2 Paquetes adicionales requeridos

Debian 13 Trixie en su instalación mínima no incluye ciertos paquetes que Kubespray necesita. Los siguientes se instalaron manualmente antes del despliegue:

```bash
# En la máquina de gestión (debian-admin)
sudo apt install -y git python3 python3-venv python3-pip ssh curl rsync

# En todos los nodos del clúster (vía Ansible desde el admin)
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m apt -a "name=rsync,apt-transport-https,gnupg2,ca-certificates state=present update_cache=yes" -b
```

La ausencia de `rsync` en particular fue una de las incidencias más persistentes durante el despliegue (ver [sección 8.4](#84-rsync-no-encontrado-en-los-nodos)).

### 4.3 Configuración de sudo sin contraseña

Para evitar conflictos de permisos durante la distribución de binarios entre nodos por rsync, se configuró sudo sin contraseña para el usuario de Ansible:

```bash
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m copy -a "content='usuario1 ALL=(ALL) NOPASSWD:ALL' dest=/etc/sudoers.d/usuario1 mode=0440" -b
```

> **Nota de seguridad**: Esta configuración es exclusiva del entorno de laboratorio. En un despliegue de producción, se restringiría a los comandos específicos que Kubespray necesita ejecutar como root, o se utilizaría un mecanismo de gestión de secretos como Vault. Ver [sección 11](#11-consideraciones-de-seguridad-laboratorio-vs-producción).

### 4.4 Resolución del hostname local

Cada nodo necesita poder resolver su propio hostname, ya que `sudo` intenta hacerlo al escalar privilegios. En Debian 13 minimal, `/etc/hosts` no siempre incluye el hostname de la máquina:

```bash
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m shell -a "hostname | xargs -I{} grep -q {} /etc/hosts || hostname | xargs -I{} sh -c 'echo 127.0.1.1 {} >> /etc/hosts'" -b
```

---

## 5. Configuración de la red con Tailscale

### 5.1 Instalación de Tailscale en cada nodo

```bash
# En cada máquina virtual
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Al ejecutar `tailscale up`, el sistema devuelve una URL de autenticación que debe completarse desde un navegador para unir el nodo a la tailnet.

### 5.2 Funcionamiento de Tailscale en el laboratorio

Tailscale crea una red mesh cifrada con WireGuard entre todas las máquinas conectadas a la misma tailnet. Cada nodo recibe una IP estable (rango `100.x.x.x`) que se mantiene independientemente de la red física subyacente.

En este laboratorio, las IPs de Tailscale se utilizan como la única dirección de comunicación entre nodos. Esto significa que:

- `ansible_host`, `ip` y `access_ip` en el inventario coinciden, ya que toda la comunicación pasa por Tailscale.
- Los nodos no necesitan estar en la misma red física ni tener IPs públicas.
- Tailscale permite MagicDNS para resolver nombres, aunque en este caso se usan directamente las IPs.

### 5.3 Configuración DNS de la tailnet

Tailscale MagicDNS toma el control del `/etc/resolv.conf` en cada nodo, redirigiendo todas las consultas DNS al resolver interno de Tailscale (`100.100.100.100`). Esto puede causar fallos transitorios de resolución DNS si el resolver tiene un micro-corte.

Para mitigar esto, se configuraron servidores DNS de respaldo globales en la consola de administración de Tailscale ([login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns)):

| Proveedor | Dirección |
|-----------|-----------|
| Google Public DNS | 8.8.8.8 |
| Cloudflare Public DNS | 1.1.1.1 |
| Quad9 Public DNS | 9.9.9.9 |

La opción "Override DNS servers" se dejó **desactivada**, de modo que MagicDNS sigue siendo el primario para nombres internos de la tailnet, pero si falla, los nodos tienen fallback a los resolvers públicos.

### 5.4 Implicaciones de Tailscale para Kubernetes

Tailscale encapsula todo el tráfico en WireGuard, lo que implica un MTU efectivo reducido (~1280 bytes frente a los 1500 habituales). Esto tiene consecuencias directas para la configuración del plugin de red de Kubernetes (Calico), ya que una doble encapsulación (WireGuard + IPIP) causa que los paquetes excedan el MTU y sean descartados. La solución adoptada se detalla en la [sección 6.4](#64-k8s-net-calicoyml--configuración-del-cni).

---

## 6. Ficheros de configuración de Kubespray

A continuación se documenta cada fichero de configuración creado en el inventario del proyecto, con explicación de cada parámetro y la razón de su elección.

### 6.1 `inventory.ini` — Inventario de nodos

**Ruta**: `kubespray/inventory/lab/inventory.ini`

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

**Explicación de las variables por host:**

| Variable | Función |
|----------|---------|
| `ansible_host` | Dirección a la que Ansible se conecta por SSH |
| `ip` | IP que Kubespray usa para el binding de servicios del nodo (kubelet, etcd) |
| `access_ip` | IP que otros nodos usan para comunicarse con este host |

Las tres coinciden porque toda la comunicación se realiza sobre la IP de Tailscale.

**Explicación de las variables globales (`[all:vars]`):**

| Variable | Función |
|----------|---------|
| `ansible_user` | Usuario SSH para todas las conexiones |
| `ansible_ssh_private_key_file` | Clave privada Ed25519 para autenticación SSH |

Se centralizan en `[all:vars]` en lugar de repetirse en cada línea para facilitar el mantenimiento.

**Explicación de los grupos:**

| Grupo | Función |
|-------|---------|
| `[kube_control_plane]` | Nodos que ejecutan el plano de control de Kubernetes (apiserver, controller-manager, scheduler) |
| `[etcd:children]` | Hereda de `kube_control_plane`: los mismos nodos ejecutan etcd (topología colocada) |
| `[kube_node]` | Nodos worker donde se ejecutan las cargas de trabajo (pods) |
| `[k8s_cluster:children]` | Agrupa control-plane y workers como miembros del clúster |

### 6.2 `all.yml` — Variables globales

**Ruta**: `kubespray/inventory/lab/group_vars/all/all.yml`

```yaml
## Descargar kubectl y kubeconfig en la máquina de gestión
kubectl_localhost: true
kubeconfig_localhost: true

## No sobrescribir hostnames del sistema
override_system_hostname: false

## Permitir Debian Trixie (no está en la lista oficial de Kubespray)
allow_unsupported_distribution_setup: true

## Activar sincronización horaria (crítico para etcd y certificados TLS)
ntp_enabled: true
ntp_manage_config: true
ntp_servers:
  - "0.es.pool.ntp.org iburst"
  - "1.es.pool.ntp.org iburst"
  - "2.es.pool.ntp.org iburst"
  - "3.es.pool.ntp.org iburst"

## Debian 13 Trixie no tiene el paquete ntp, usar chrony
ntp_package: chrony
```

**Justificación de cada parámetro:**

| Parámetro | Valor | Justificación |
|-----------|-------|---------------|
| `kubectl_localhost` | `true` | Descarga `kubectl` en la máquina admin y genera un script helper `kubectl.sh` en los artifacts |
| `kubeconfig_localhost` | `true` | Copia `admin.conf` (credenciales de administración del clúster) a los artifacts |
| `override_system_hostname` | `false` | Evita que Kubespray modifique los hostnames configurados en el SO |
| `allow_unsupported_distribution_setup` | `true` | Debian 13 Trixie no está en la lista oficial de distribuciones soportadas por Kubespray. Sin este flag, el playbook aborta en la fase de validación |
| `ntp_enabled` | `true` | Activa la sincronización horaria. etcd es especialmente sensible a la deriva de reloj: un desfase de pocos segundos entre nodos causa rechazos de heartbeats y fallos de elección de líder |
| `ntp_manage_config` | `true` | Kubespray gestiona el fichero de configuración de chrony automáticamente |
| `ntp_servers` | Pool de España | Servidores NTP geográficamente cercanos (España) para menor latencia |
| `ntp_package` | `chrony` | Debian 13 Trixie ha eliminado el paquete `ntp` de sus repositorios. `chrony` es su sustituto oficial y ofrece mejor precisión en entornos virtualizados |

### 6.3 `download.yml` — Configuración de descargas

**Ruta**: `kubespray/inventory/lab/group_vars/all/download.yml`

```yaml
## Descargar binarios e imágenes una sola vez en el primer nodo
## y distribuirlos al resto. Evita rate-limiting en los CDN.
download_run_once: true
```

**Justificación:**

Sin esta opción, cada uno de los 7 nodos descarga independientemente los mismos binarios (containerd, runc, crictl, kubectl, kubeadm, etc.) e imágenes de contenedor desde los CDN de GitHub y los registros de imágenes. Con 7 nodos descargando en paralelo desde la misma dirección IP pública, los CDN aplican rate-limiting (especialmente Cloudflare, que protege `dl.k8s.io` y `github.com`), causando fallos intermitentes en la fase de descarga.

Con `download_run_once: true`, los binarios se descargan una sola vez en el primer nodo del clúster y se distribuyen al resto mediante rsync sobre SSH.

> **Nota**: Inicialmente se configuró también `download_localhost: true` para que la descarga ocurriera en la máquina admin. Esta opción fue descartada porque rsync desde localhost a los nodos ejecutaba la copia como usuario no privilegiado (`usuario1`), pero el directorio de destino (`/tmp/releases`) era creado por Ansible con permisos de root, causando errores de `Permission denied`. Sin `download_localhost`, la descarga ocurre en el primer nodo del clúster con privilegios de become (root), eliminando el conflicto de permisos.

### 6.4 `k8s-net-calico.yml` — Configuración del CNI

**Ruta**: `kubespray/inventory/lab/group_vars/k8s_cluster/k8s-net-calico.yml`

```yaml
## Calico sobre Tailscale: usar VXLAN en vez de IPIP
## Tailscale ya encapsula en WireGuard. IPIP dentro de WireGuard
## causa doble encapsulación y problemas de MTU.

# Desactivar BGP (no necesario con VXLAN)
calico_network_backend: vxlan

# Desactivar IPIP
calico_ipip_mode: 'Never'

# Activar VXLAN entre todos los nodos
calico_vxlan_mode: 'Always'

# MTU del veth de los pods.
# Tailscale tiene MTU efectivo ~1280.
# VXLAN resta 50 bytes → 1280 - 50 = 1230
calico_veth_mtu: 1230
```

**Justificación técnica detallada:**

Este es el fichero de configuración más crítico para el correcto funcionamiento de Kubernetes sobre Tailscale. El problema que resuelve es el siguiente:

1. **Calico por defecto usa IPIP**: La configuración por defecto de Calico en Kubespray activa la encapsulación IP-in-IP (IPIP) con backend BGP. IPIP encapsula cada paquete de red entre pods en un paquete IP adicional, añadiendo 20 bytes de cabecera.

2. **Tailscale usa WireGuard**: Todo el tráfico entre nodos de la tailnet viaja encapsulado dentro de túneles WireGuard, que añaden su propia cabecera (~60 bytes).

3. **Doble encapsulación = problemas de MTU**: Con IPIP dentro de WireGuard, un paquete de datos que originalmente tiene 1500 bytes pasa a tener 1500 + 20 (IPIP) + 60 (WireGuard) = 1580 bytes, excediendo el MTU de la red física. Los paquetes que superan el MTU se fragmentan o se descartan silenciosamente, causando que los pods de diferentes nodos no puedan comunicarse (los pods del mismo nodo funcionan correctamente porque no usan el túnel).

4. **Solución**: Se cambia la encapsulación de IPIP a VXLAN, se desactiva BGP (innecesario con VXLAN) y se fija el MTU del veth de los pods a 1230 bytes (MTU de Tailscale ~1280 menos 50 bytes de cabecera VXLAN).

### 6.5 `k8s-cluster.yml` — Configuración general del clúster

**Ruta**: `kubespray/inventory/lab/group_vars/k8s_cluster/k8s-cluster.yml`

```yaml
## Plugin de red
kube_network_plugin: calico

## Rango de IPs para servicios internos de Kubernetes
kube_service_addresses: 10.233.0.0/18

## Rango de IPs para pods
kube_pods_subnet: 10.233.64.0/18

## Prefijo de red por nodo (cada nodo obtiene un /24 para sus pods)
kube_network_node_prefix: 24

## Runtime de contenedores
container_manager: containerd

## Modo del proxy de Kubernetes
kube_proxy_mode: ipvs

## DNS interno del clúster
cluster_name: cluster.local
dns_mode: coredns
enable_nodelocaldns: true
nodelocaldns_ip: 169.254.25.10

## Resolución DNS
resolvconf_mode: host_resolvconf
```

**Justificación de cada parámetro:**

| Parámetro | Valor | Justificación |
|-----------|-------|---------------|
| `kube_network_plugin` | `calico` | CNI maduro y ampliamente adoptado en producción. Soporta Network Policies para segmentación de red |
| `kube_service_addresses` | `10.233.0.0/18` | Rango de IPs virtuales para los Services internos de Kubernetes (16.382 IPs). No debe colisionar con la red física ni con la tailnet |
| `kube_pods_subnet` | `10.233.64.0/18` | Rango de IPs asignadas a los pods (16.382 IPs). Cada nodo recibe un bloque /24 (254 pods por nodo) |
| `kube_network_node_prefix` | `24` | Tamaño del bloque CIDR asignado a cada nodo. Un /24 permite hasta 254 pods por nodo |
| `container_manager` | `containerd` | Runtime estándar de Kubernetes desde la deprecación de dockershim en v1.24. Más ligero y con menor superficie de ataque que Docker |
| `kube_proxy_mode` | `ipvs` | Utiliza IPVS del kernel Linux para el balanceo de servicios. Mayor rendimiento y escalabilidad que iptables, especialmente con muchos Services |
| `cluster_name` | `cluster.local` | Dominio DNS interno del clúster (valor estándar) |
| `dns_mode` | `coredns` | Servidor DNS del clúster. Estándar en Kubernetes |
| `enable_nodelocaldns` | `true` | Caché DNS local en cada nodo que reduce la latencia de resolución y la carga sobre CoreDNS |
| `resolvconf_mode` | `host_resolvconf` | Utiliza el `/etc/resolv.conf` del host como base para la configuración DNS de los pods |

---

## 7. Proceso de instalación paso a paso

### 7.1 Preparación de la máquina de gestión

```bash
# Instalar herramientas base
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip ssh curl rsync

# Clonar Kubespray
cd ~
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# Crear y activar entorno virtual de Python
python3 -m venv .venv
source .venv/bin/activate

# Instalar dependencias de Kubespray
pip install -U pip
pip install -r requirements.txt

# Verificar instalación
ansible --version
# ansible [core 2.18.14]
```

### 7.2 Clonar el repositorio del proyecto

```bash
cd ~
git clone git@github.com:manusolmel/pim_infra_multinodo.git
```

La configuración del inventario ya se encuentra en `~/pim_infra_multinodo/kubespray/inventory/lab/`.

### 7.3 Verificación de conectividad

Antes de cualquier despliegue, se verifica que Ansible puede conectar y ejecutar comandos con privilegios en todos los nodos:

```bash
cd ~/kubespray
source .venv/bin/activate

# Test de conectividad SSH + sudo
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all -m ping -b
```

Resultado esperado: los 7 nodos devuelven `"pong"` con `SUCCESS`.

### 7.4 Verificación de la configuración

Antes de lanzar el despliegue, se verifica que Ansible está leyendo correctamente las variables del inventario:

```bash
ansible-inventory -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini --list | head -30
```

Se debe confirmar la presencia de las variables clave: `allow_unsupported_distribution_setup: true`, `ntp_enabled: true`, `ntp_package: chrony`, `calico_vxlan_mode: Always`, `download_run_once: true`, etc.

### 7.5 Ejecución del despliegue

```bash
cd ~/kubespray
source .venv/bin/activate

ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini \
  cluster.yml -b \
  2>&1 | tee ~/pim_infra_multinodo/logs/deploy_$(date +%Y%m%d_%H%M%S).log
```

El playbook `cluster.yml` ejecuta las siguientes fases principales:

1. **Validación del inventario**: Comprueba la versión de Ansible, la estructura del inventario, la compatibilidad de la distribución y los rangos de red.
2. **Bootstrap de los nodos**: Instala paquetes del sistema, configura chrony, habilita ip_forwarding, configura sysctl.
3. **Descarga de binarios e imágenes**: Descarga containerd, runc, crictl, kubeadm, kubectl, y las imágenes de sistema (kube-apiserver, kube-proxy, etcd, CoreDNS, Calico, etc.).
4. **Instalación del runtime de contenedores**: Instala y configura containerd.
5. **Configuración de etcd**: Despliega el clúster etcd de 3 nodos con certificados TLS.
6. **Despliegue del plano de control**: Inicializa kubeadm en el primer control-plane y une los otros dos.
7. **Unión de los workers**: Los nodos worker se unen al clúster.
8. **Despliegue de la red (Calico)**: Instala el plugin CNI con la configuración VXLAN.
9. **Despliegue de DNS (CoreDNS + nodelocaldns)**: Instala los componentes de resolución DNS interna.
10. **Generación de artefactos**: Copia `admin.conf` y genera `kubectl.sh` en el directorio de artifacts.

**Resultado del despliegue exitoso** (14 de marzo de 2026):

| Nodo | ok | changed | failed | skipped |
|------|-----|---------|--------|---------|
| debian-nodo1 | 485 | 108 | 0 | 401 |
| debian-nodo2 | 472 | 109 | 0 | 396 |
| debian-nodo3 | 472 | 109 | 0 | 396 |
| debian-nodo4 | 472 | 109 | 0 | 396 |
| debian-nodo5 | 782 | 226 | 0 | 672 |
| debian-nodo6 | 578 | 147 | 0 | 653 |
| debian-nodo7 | 580 | 148 | 0 | 651 |

**Tiempo total de despliegue**: 24 minutos y 17 segundos.

**Tareas más costosas en tiempo**:
- Configuración de DNS (`resolv.conf`): ~76s
- Espera del API server: ~56s
- Descarga e inyección de imágenes de contenedor: ~43s cada una
- Unión de control-plane al clúster: ~26s
- Inicialización del primer control-plane (kubeadm init): ~14s

### 7.6 Configuración de kubectl post-despliegue

```bash
# Copiar kubeconfig a la ruta estándar
mkdir -p ~/.kube
cp ~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/admin.conf ~/.kube/config

# Añadir kubectl.sh al PATH
export PATH=$PATH:~/pim_infra_multinodo/kubespray/inventory/lab/artifacts/

# Verificar acceso
kubectl.sh get nodes
```

---

## 8. Incidencias encontradas y resolución

Durante el proceso de despliegue se encontraron varias incidencias, todas ellas derivadas de la combinación de Debian 13 Trixie (distribución no oficialmente soportada por Kubespray) y Tailscale como red de interconexión. Se documentan aquí como referencia para futuros despliegues similares.

### 8.1 Distribución no soportada

**Síntoma**: El playbook aborta en la fase de validación con un error de assertion indicando que la distribución no es compatible.

**Causa raíz**: Kubespray mantiene una lista interna de distribuciones soportadas (Debian 11/12, Ubuntu 22.04/24.04, CentOS, Rocky, etc.). Debian 13 Trixie, al ser una versión reciente, no está incluida.

**Resolución**: Añadir `allow_unsupported_distribution_setup: true` en `group_vars/all/all.yml`. Esta variable indica a Kubespray que continúe el despliegue aunque la distribución no esté en su lista oficial.

**Impacto**: Ninguno funcional. Debian 13 es plenamente compatible con todos los componentes del clúster.

### 8.2 Paquete NTP no disponible en Debian 13

**Síntoma**: Fallo en la tarea `system_packages : Manage packages` con el error `No package matching 'ntp' is available` en todos los nodos.

**Causa raíz**: Debian 13 Trixie ha eliminado el paquete `ntp` (ntpd clásico) de sus repositorios, sustituyéndolo por `chrony`. Cuando se activa `ntp_enabled: true`, Kubespray intenta instalar el paquete `ntp` por defecto.

**Resolución**: Añadir `ntp_package: chrony` en `group_vars/all/all.yml`. Esta variable se encontró inspeccionando los defaults de Kubespray:

```bash
grep -r "ntp_package" ~/kubespray/roles/kubespray_defaults/ --include="*.yml"
```

**Impacto**: chrony es funcionalmente superior a ntpd en entornos virtualizados y su configuración es gestionada automáticamente por Kubespray.

### 8.3 Rate-limiting en las descargas de binarios

**Síntoma**: Fallos intermitentes en la tarea `Download_file | Download item` al intentar descargar binarios desde `dl.k8s.io` y `github.com`.

**Causa raíz**: Sin `download_run_once`, los 7 nodos descargan los mismos ficheros simultáneamente desde la misma IP pública. Los CDN (especialmente Cloudflare) aplican rate-limiting, rechazando las peticiones excedentes.

**Resolución**: Añadir `download_run_once: true` en `group_vars/all/download.yml`. Los binarios se descargan una sola vez y se distribuyen por SSH al resto.

### 8.4 rsync no encontrado en los nodos

**Síntoma**: Fallo en la tarea `Download_file | Copy file from cache to nodes` con el error `Failed to find required executable "rsync"`.

**Causa raíz**: La distribución de binarios entre nodos con `download_run_once: true` utiliza `rsync` como mecanismo de copia. La instalación mínima de Debian 13 no incluye `rsync`, y tampoco lo instala Kubespray automáticamente como dependencia.

**Resolución**: Instalar `rsync` en todos los nodos Y en la máquina admin antes de ejecutar el playbook:

```bash
# En la máquina admin
sudo apt install -y rsync

# En todos los nodos del clúster
ansible all -m apt -a "name=rsync state=present" -b
```

**Lección aprendida**: Cuando se usa `download_run_once`, rsync debe estar presente en ambos extremos de la copia (origen y destino).

### 8.5 Permisos denegados en `/tmp/releases`

**Síntoma**: Fallo en la tarea `Download_file | Copy file from cache to nodes` con el error `rsync: [receiver] mkstemp "/tmp/releases/.runc-1.3.4.amd64" failed: Permission denied (13)`.

**Causa raíz**: El directorio `/tmp/releases/` fue creado en un intento anterior del playbook con permisos de root (vía `become`). Al relanzar el playbook, la copia por rsync intentaba escribir como `usuario1` (sin become en la operación de rsync), fallando por permisos.

Inicialmente se había configurado `download_localhost: true`, que descargaba los binarios en la máquina admin y los copiaba a los nodos con rsync. El rsync se ejecutaba como `usuario1` pero el directorio destino pertenecía a root.

**Resolución**: Se eliminó `download_localhost: true` del fichero `download.yml`, dejando solo `download_run_once: true`. De este modo, la descarga ocurre en el primer nodo del clúster (con privilegios de root vía become) y la distribución al resto también se realiza con become, evitando conflictos de permisos.

Adicionalmente, fue necesario limpiar los directorios residuales de intentos anteriores:

```bash
# Limpiar en todos los nodos
ansible all -m shell -a "rm -rf /tmp/releases" -b

# Limpiar en la máquina admin
rm -rf /tmp/kubespray_cache
```

### 8.6 Sudo no puede resolver el hostname

**Síntoma**: Error `sudo: unable to resolve host debian-nodo5: Nombre o servicio desconocido` durante la copia de binarios.

**Causa raíz**: En Debian 13 minimal, el hostname de la máquina no siempre está incluido en `/etc/hosts`. Cuando sudo intenta resolver el hostname del nodo local para escribir en los logs de autenticación, falla si no hay una entrada correspondiente.

**Resolución**: Asegurar que cada nodo tiene su hostname en `/etc/hosts`:

```bash
ansible all -m shell -a "hostname | xargs -I{} grep -q {} /etc/hosts || \
  hostname | xargs -I{} sh -c 'echo 127.0.1.1 {} >> /etc/hosts'" -b
```

### 8.7 Fallos de DNS transitorios con Tailscale MagicDNS

**Síntoma**: Fallo intermitente en `apt-get update` con `Failed to update apt cache` en uno o más nodos.

**Causa raíz**: Tailscale MagicDNS configura `100.100.100.100` como único nameserver en `/etc/resolv.conf`. Si el resolver de Tailscale tiene un micro-corte, todas las consultas DNS del nodo fallan, incluyendo la resolución de los repositorios de Debian.

**Resolución**: Configurar servidores DNS de respaldo globales en la consola de administración de Tailscale (DNS → Nameservers → Add nameserver):
- Google Public DNS: `8.8.8.8`
- Cloudflare Public DNS: `1.1.1.1`
- Quad9 Public DNS: `9.9.9.9`

Con "Override DNS servers" desactivado, MagicDNS sigue siendo primario pero los fallbacks entran en juego automáticamente.

### 8.8 Desfase horario entre nodos (certificados TLS)

**Síntoma**: El nodo 3 no pudo unirse al clúster con el error `x509: certificate has expired or is not yet valid: current time 2026-03-12T20:45:41+01:00 is before 2026-03-14T10:14:41Z`.

**Causa raíz**: El reloj del nodo 3 estaba adelantado/atrasado respecto a los nodos del plano de control. Los certificados TLS generados por kubeadm tienen un timestamp de validez que no coincidía con la hora del nodo que intentaba unirse.

**Causa raíz confirmada**: VirtualBox. Cuando se pausa o se guarda el estado de una máquina virtual, el reloj del guest se congela. Al reanudarla, el reloj queda en la fecha en que se pausó. chrony lo corrige eventualmente, pero si kubeadm intenta validar certificados TLS antes de que chrony sincronice, el desfase causa el rechazo.

**Resolución**: Forzar la sincronización horaria en todos los nodos antes de cualquier despliegue:

```bash
ansible all -m shell -a "chronyc makestep && sleep 2 && date" -b
```

**Prevención**: No pausar las VMs de VirtualBox; apagarlas con `shutdown` o dejarlas corriendo. Antes de cualquier operación del clúster, verificar la sincronización:

```bash
ansible all -m command -a "chronyc tracking" -b
```

### 8.9 CNI no desplegado por fallo en fase de control-plane

**Síntoma**: Tras un despliegue parcialmente exitoso (6 de 7 nodos unidos), todos los nodos aparecían en estado `NotReady` con el mensaje `NetworkPluginNotReady: cni plugin not initialized`. No existía ningún pod de Calico en el clúster.

**Causa raíz**: El playbook falló al intentar unir el nodo 3 (por el desfase horario de la incidencia 8.8). Al relanzar `cluster.yml`, la fase `Wait for new control plane nodes to be Ready` agotó los reintentos esperando que los control-plane pasaran a `Ready`, pero nunca lo harían porque Calico no estaba desplegado, y Calico no se desplegaba porque el playbook no llegaba a esa fase.

**Intento de resolución manual**: Se intentó instalar Calico manualmente con el operador Tigera, pero el CRD `installations.operator.tigera.io` excedía el límite de 256KB en annotations de Kubernetes. Se cambió al manifiesto estándar de Calico (`calico.yaml`), que sí funcionó y puso todos los nodos en `Ready`.

**Resolución definitiva**: Aunque la instalación manual de Calico funcionó, creaba una inconsistencia con la gestión de Kubespray (que espera ser el gestor exclusivo de Calico). La solución correcta fue realizar un **reset completo** (`reset.yml`) y relanzar `cluster.yml` desde cero con todos los prerequisitos ya resueltos (chrony sincronizado, rsync instalado, NOPASSWD configurado, hostnames en `/etc/hosts`).

**Lección aprendida**: Ante un despliegue parcial con componentes críticos faltantes, es preferible un reset limpio frente a intentar reparar manualmente. Kubespray es idempotente pero espera ser el gestor único de todos los componentes del clúster.

---

## 9. Verificación del clúster

### 9.1 Estado de los nodos

```bash
kubectl.sh get nodes
```

Resultado del despliegue exitoso (14 de marzo de 2026):

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

> **Nota**: Los nodos worker aparecen sin rol (`<none>`) porque Kubernetes solo asigna automáticamente el label `control-plane`. Esto es puramente cosmético y no afecta al funcionamiento. Si se desea etiquetar los workers:
> ```bash
> kubectl label node debian-nodo1 node-role.kubernetes.io/worker=""
> ```

### 9.2 Pods del sistema

```bash
kubectl.sh get pods -A
```

Resultado del despliegue exitoso — todos los pods en estado `Running`:

```
NAMESPACE     NAME                                          READY   STATUS    AGE
kube-system   calico-kube-controllers-5bc89bc76-66rr2       1/1     Running   7m41s
kube-system   calico-node-2crb7                             1/1     Running   7m59s
kube-system   calico-node-4t7zb                             1/1     Running   7m59s
kube-system   calico-node-7sdmz                             1/1     Running   7m59s
kube-system   calico-node-dh6zj                             1/1     Running   7m59s
kube-system   calico-node-j2s47                             1/1     Running   7m59s
kube-system   calico-node-mb4ws                             1/1     Running   7m59s
kube-system   calico-node-pnvmf                             1/1     Running   7m59s
kube-system   coredns-58cc5d8ddf-dcjm4                      1/1     Running   7m32s
kube-system   coredns-58cc5d8ddf-gntmq                      1/1     Running   3m40s
kube-system   dns-autoscaler-5654b864c-4ml78                1/1     Running   7m27s
kube-system   kube-apiserver-debian-nodo5                   1/1     Running   9m39s
kube-system   kube-apiserver-debian-nodo6                   1/1     Running   9m21s
kube-system   kube-apiserver-debian-nodo7                   1/1     Running   9m4s
kube-system   kube-controller-manager-debian-nodo5          1/1     Running   9m39s
kube-system   kube-controller-manager-debian-nodo6          1/1     Running   9m21s
kube-system   kube-controller-manager-debian-nodo7          1/1     Running   9m4s
kube-system   kube-proxy (×7)                               1/1     Running   ~8m
kube-system   kube-scheduler-debian-nodo5                   1/1     Running   9m39s
kube-system   kube-scheduler-debian-nodo6                   1/1     Running   9m21s
kube-system   kube-scheduler-debian-nodo7                   1/1     Running   9m4s
kube-system   nginx-proxy-debian-nodo1                      1/1     Running   8m45s
kube-system   nginx-proxy-debian-nodo2                      1/1     Running   8m45s
kube-system   nginx-proxy-debian-nodo3                      1/1     Running   8m45s
kube-system   nginx-proxy-debian-nodo4                      1/1     Running   8m44s
kube-system   nodelocaldns (×7)                             1/1     Running   ~7m
```

Resumen de pods del sistema operativos:

| Componente | Instancias | Distribución |
|-----------|-----------|-------------|
| calico-node | 7 | Uno por nodo (DaemonSet) |
| calico-kube-controllers | 1 | Control-plane |
| kube-apiserver | 3 | Uno por control-plane |
| kube-controller-manager | 3 | Uno por control-plane |
| kube-scheduler | 3 | Uno por control-plane |
| kube-proxy | 7 | Uno por nodo (DaemonSet) |
| coredns | 2 | Réplicas gestionadas por dns-autoscaler |
| dns-autoscaler | 1 | Ajusta réplicas de CoreDNS según tamaño del clúster |
| nodelocaldns | 7 | Uno por nodo (DaemonSet) |
| nginx-proxy | 4 | Uno por worker (proxy HA del API server) |

### 9.3 Prueba funcional de despliegue y escalado

Se realizó una prueba de despliegue y escalado para validar el funcionamiento del scheduler:

```bash
kubectl create deployment nginx --image=nginx
kubectl scale deployment nginx --replicas=4
kubectl get pods -o wide
```

Resultado real:

```
NAME                     READY   STATUS    NODE            IP
nginx-56c45fd5ff-cdjth   1/1     Running   debian-nodo4    10.233.110.4
nginx-56c45fd5ff-kppwl   1/1     Running   debian-nodo3    10.233.117.129
nginx-56c45fd5ff-npfg8   1/1     Running   debian-nodo2    10.233.66.129
nginx-56c45fd5ff-phlzc   1/1     Running   debian-nodo1    10.233.114.130
```

Las 4 réplicas se distribuyeron automáticamente una por cada worker, confirmando:
1. El scheduler acepta y programa cargas de trabajo correctamente.
2. Kubernetes crea múltiples réplicas del mismo servicio.
3. Los pods se distribuyen equitativamente entre todos los nodos worker disponibles.
4. Cada pod recibe una IP del rango `kube_pods_subnet` (10.233.64.0/18) configurado.

### 9.4 Prueba de alta disponibilidad

Para demostrar la HA ante el comité de defensa, se puede simular la caída de un pod o un nodo:

```bash
# Eliminar un pod manualmente y observar la recreación automática
kubectl delete pod <nombre-del-pod>
kubectl get pods -w  # -w activa watch mode para ver la recreación en tiempo real
```

---

## 10. Escalabilidad del clúster

Kubespray proporciona playbooks específicos para operaciones de escalado:

### 10.1 Añadir workers

1. Añadir el nuevo nodo a `[all]` y `[kube_node]` en `inventory.ini`.
2. Refrescar los facts:
   ```bash
   ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini facts.yml -b
   ```
3. Ejecutar el playbook de escalado:
   ```bash
   ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini scale.yml -b
   ```

### 10.2 Añadir nodos control-plane

Para añadir control-plane se usa `cluster.yml` (no `scale.yml`). Los nuevos nodos deben añadirse al final del grupo `[kube_control_plane]` para respetar el orden de inicialización.

### 10.3 Eliminar nodos

```bash
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini \
  remove-node.yml -b -e node=<nombre-del-nodo>
```

### 10.4 Consideraciones sobre etcd

El número de nodos etcd debe mantenerse **siempre impar** (1, 3, 5, 7...) para garantizar el quórum. Con 3 nodos, el clúster tolera la pérdida de 1. Con 5, tolera la pérdida de 2.

---

## 11. Consideraciones de seguridad: laboratorio vs. producción

La configuración actual está optimizada para un entorno de laboratorio educativo. A continuación se documentan las decisiones de seguridad tomadas y sus alternativas para un entorno de producción:

| Aspecto | Laboratorio (actual) | Producción (recomendado) |
|---------|---------------------|--------------------------|
| Sudo | NOPASSWD para `usuario1` | Lista explícita de comandos permitidos en sudoers, o uso de Ansible Vault para contraseñas |
| DNS | Fallback a resolvers públicos (8.8.8.8, 1.1.1.1, 9.9.9.9) | Resolvers DNS privados corporativos con DNSSEC |
| Tailscale | Cuenta personal, ACLs por defecto | Tailscale Teams/Enterprise con ACLs granulares por servicio |
| Certificados TLS | Generados automáticamente por kubeadm (auto-firmados) | Certificados emitidos por una CA corporativa con rotación automática |
| Acceso al API server | `admin.conf` copiado al admin | RBAC con usuarios/ServiceAccounts individuales y permisos mínimos |
| Network Policies | No configuradas | Políticas Calico para segmentar tráfico entre namespaces |
| Cifrado de secretos | Desactivado (`kube_encrypt_secret_data: false`) | Activar cifrado at-rest con KMS |
| Monitorización | Pendiente de despliegue | Prometheus + Grafana + Alertmanager con alertas operativas |

---

## 12. Resumen de decisiones técnicas

| Decisión | Alternativas consideradas | Elección | Razón |
|----------|--------------------------|----------|-------|
| Orquestador | Docker Compose, Docker Swarm, K3s | Kubernetes (Kubespray) | Estándar de la industria para hosting; HA nativa, escalado declarativo, almacenamiento persistente |
| Herramienta de despliegue | kubeadm manual, K3s, RKE2 | Kubespray + Ansible | Automatización completa, producción-ready, integración con Ansible |
| CNI | Flannel, Cilium, Calico | Calico (VXLAN) | Maduro, soporta Network Policies, compatible con overlay WireGuard de Tailscale |
| Encapsulación CNI | IPIP, VXLAN, ninguna | VXLAN | Evita doble encapsulación IPIP+WireGuard; MTU predecible |
| Runtime de contenedores | Docker, CRI-O, containerd | containerd | Estándar de Kubernetes desde v1.24; menor overhead |
| Modo kube-proxy | iptables, ipvs, nftables | IPVS | Mayor rendimiento y escalabilidad con muchos Services |
| Sincronización horaria | ntpd, systemd-timesyncd, chrony | chrony | Único disponible en Debian 13 Trixie; mejor precisión en VMs |
| Red entre nodos | VPN punto a punto, VLAN, red plana | Tailscale (WireGuard mesh) | IP estable, NAT traversal, cifrado automático, fácil despliegue |
| Distribución | Ubuntu 24.04, Debian 12, Debian 13 | Debian 13 Trixie | Decisión del equipo; demostración de adaptación a distribuciones no soportadas oficialmente |
| Descargas | Paralela, run_once+localhost, run_once | download_run_once | Evita rate-limiting sin conflictos de permisos |

---

## Anexo A: Versiones del software utilizado

| Componente | Versión |
|------------|---------|
| Debian | 13.3.0 (Trixie) amd64 |
| Kernel Linux | 6.12.73+deb13 |
| VirtualBox | Última versión disponible |
| Tailscale | 1.94.2 |
| Kubespray | master (commit `da6539c7a`) |
| Ansible | core 2.18.14 |
| Python | 3.13.5 |
| Kubernetes | v1.35.1 |
| containerd | Versión desplegada por Kubespray |
| Calico | Versión desplegada por Kubespray |
| chrony | Paquete de Debian 13 |

## Anexo B: Referencia rápida de comandos

```bash
# === PREPARACIÓN ===
cd ~/kubespray && source .venv/bin/activate

# === VERIFICACIÓN ===
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all -m ping -b
ansible-inventory -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini --list | head -30

# === DESPLIEGUE ===
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini cluster.yml -b

# === ESCALADO (añadir workers) ===
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini scale.yml -b

# === ELIMINACIÓN DE NODOS ===
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini remove-node.yml -b -e node=<nodo>

# === RESET COMPLETO ===
ansible-playbook -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini reset.yml -b -e reset_confirmation=yes

# === VERIFICACIÓN DEL CLÚSTER ===
kubectl.sh get nodes
kubectl.sh get pods -A
kubectl.sh get pods -o wide

# === PRUEBA FUNCIONAL ===
kubectl create deployment nginx --image=nginx
kubectl scale deployment nginx --replicas=4
kubectl get pods -o wide
```
