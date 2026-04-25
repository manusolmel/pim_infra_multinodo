# Infraestructura de Hosting Multinodo

Proyecto fin de ciclo ASIR orientado al diseño, despliegue y operación de una infraestructura distribuida de hosting con alta disponibilidad, pensada como solución escalable y robusta para distintos servicios dentro de una red privada.

El proyecto se define como una plataforma de hosting multinodo basada en **Kubernetes sobre Debian 13**, con **red privada Tailscale**, **despliegue automatizado con Kubespray/Ansible**, **almacenamiento persistente con Longhorn** y **balanceador de entrada privado mediante Tailscale Kubernetes Operator**.

## Arquitectura

```
                    ┌──────────────────────────────────────┐
                    │          Tailscale Tailnet           │
                    │     VPN mesh cifrada (WireGuard)     │
                    └──┬───────┬──────┬──────┬───────┬─────┘
                       │       │      │      │       │
              ┌────────┴───┐ ┌─┴────┐ │   ┌──┴───┐ ┌─┴──────┐
              │debian-admin│ │nodo5 │ │   │nodo6 │ │nodo7   │
              │  Ansible   │ │ CP+  │ │   │ CP+  │ │ CP+    │
              │  Kubespray │ │ etcd │ │   │ etcd │ │ etcd   │
              └────────────┘ └──────┘ │   └──────┘ └────────┘
                                      │
                    ┌─────────┬───────┼───────┬─────────┐
                    │         │       │       │         │
                 ┌──┴────┐ ┌──┴───┐ ┌─┴────┐ ┌┴───────┐
                 │nodo1  │ │nodo2 │ │nodo3 │ │nodo4   │
                 │Worker │ │Worker│ │Worker│ │Worker  │
                 └───────┘ └──────┘ └──────┘ └────────┘
```

**8 VMs** (VirtualBox) · **Debian 13.3 Trixie** · **Kubernetes v1.35.1** · **Calico VXLAN** · **containerd** · **chrony**

## Stack tecnológico

### Actualmente implementado

| Capa | Tecnología |
|------|------------|
| Virtualización | Oracle VirtualBox |
| Sistema operativo | Debian 13.3 (Trixie) |
| Red privada entre nodos | Tailscale (WireGuard) |
| Automatización y despliegue | Ansible + Kubespray |
| Orquestación de contenedores | Kubernetes v1.35.1 |
| Red del clúster (CNI) | Calico |
| Encapsulación de red entre pods | VXLAN |
| Runtime de contenedores | containerd |
| Balanceo interno de Services | kube-proxy en modo IPVS |
| DNS interno del clúster | CoreDNS + nodelocaldns |
| Sincronización horaria | chrony |
| Almacenamiento persistente | Longhorn |
| Balanceador de entrada privado | Tailscale Kubernetes Operator + ProxyGroup HA |

### Ampliaciones previstas

> Pendiente de implementación o cierre funcional:
>
> - Prometheus + Grafana
> - Network Policies con Calico

## Documentación

| Documento                                                             | Descripción                                                                          |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| [01 — Instalación de VMs](docs/01_instalacion_vms.md)                 | Creación de VMs en VirtualBox, instalación de Debian 13 y configuración de Tailscale |
| [02 — Nodo de administración](docs/02_nodo_administracion.md)         | Preparación del admin: Ansible, Kubespray, claves SSH, preparación de nodos remotos  |
| [03 — Despliegue de Kubespray](docs/03_despliegue_kubespray.md)       | Configuración, ejecución, verificación, incidencias y decisiones técnicas            |
| [04 — Referencia de comandos](docs/04_comandos.md)                    | Comandos de despliegue y comandos operativos del día a día                           |
| [05 — Ficha técnica y red](docs/05_ficha_tecnica_red.md)              | Inventario de nodos, versiones de software, configuración de red y mapa              |
| [06 — Guía paso a paso](docs/06_guia_paso_a_paso.md)                  | Checklist completa para reproducir el despliegue desde cero                          |
| [07 — Balanceador de carga privado](docs/07_balanceador_tailscale.md) | Instalación y despliegue del sistema de balanceo de carga privado con Tailscale      |
| [08 — Almacenamiento persistente con Longhorn](docs/08_longhorn.md)   | Instalación, configuración y verificación del sistema de almacenamiento persistente   |
| [09 — WordPress + MariaDB con Helm](docs/09_wordpress_mariadb_helm.md) | Despliegue funcional de WordPress + MariaDB con Helm, Longhorn y Tailscale           |
| [10 — Pruebas de evaluación entrega 5](docs/10_pruebas_entrega5.md)   | Índice de evidencias, scripts y resultados de la fase de pruebas                     |

## Estructura del repositorio

```
pim_infra_multinodo/
├── README.md                          ← Este fichero
├── docs/
│   ├── 01_instalacion_vms.md
│   ├── 02_nodo_administracion.md
│   ├── 03_despliegue_kubespray.md
│   ├── 04_comandos.md
│   ├── 05_ficha_tecnica_red.md
│   ├── 06_guia_paso_a_paso.md
│   ├── 07_balanceador_tailscale.md
│   ├── 08_longhorn.md
│   ├── 09_wordpress_mariadb_helm.md
│   └── 10_pruebas_entrega5.md
├── evidencias/
│   ├── scripts/
│   └── testing/
├── kubespray/
│   └── inventory/
│       └── lab/
│           ├── inventory.ini
│           └── group_vars/
│               ├── all/
│               │   ├── all.yml
│               │   └── download.yml
│               └── k8s_cluster/
│                   ├── k8s-cluster.yml
│                   └── k8s-net-calico.yml
├── manifests/
│   ├── longhorn/
│   ├── tailscale/
│   ├── testing/
│   └── wordpress_mariadb/
├── logs/                              ← Logs de despliegue (excluidos de git)
└── .gitignore
```

Kubespray se clona como repositorio independiente (`~/kubespray`) y no se modifica. Los playbooks se ejecutan desde allí apuntando al inventario de este repositorio con `-i`.

## Estado actual

- [x] Laboratorio multinodo sobre 8 VMs
- [x] Clúster Kubernetes funcional (3 control-plane + 4 workers)
- [x] Red privada Tailscale operativa
- [x] Despliegue automatizado con Kubespray
- [x] Verificación funcional inicial del clúster (nginx ×4 réplicas)
- [x] Almacenamiento persistente con Longhorn desplegado
- [x] `StorageClass` `longhorn` configurada como clase por defecto
- [x] Publicación privada de la UI de Longhorn mediante `Service` `LoadBalancer` sobre Tailscale
- [x] Sistema de balanceo de entrada privado implantado con Tailscale Operator
- [x] Capa de entrada redundante mediante ProxyGroup
- [x] Publicación privada de interfaces internas mediante `Service` `LoadBalancer`
- [x] WordPress + MariaDB desplegado mediante Helm, Longhorn y Tailscale
- [x] Documentación técnica del despliegue base, del balanceador, del almacenamiento persistente y del servicio WordPress
- [x] Fase de pruebas de evaluación documentada con evidencias reproducibles

## Próximos pasos

- [ ] Prometheus + Grafana
- [ ] Network Policies con Calico
- [ ] Integración de más servicios reales sobre el balanceador privado
- [ ] Preparación de la defensa final

## Inicio rápido

```bash
# En debian-admin
cd ~/kubespray
source .venv/bin/activate

# Verificar conectividad
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all -m ping -b

# Ver estado del clúster
kubectl get nodes
kubectl get pods -A

# Ver estado del almacenamiento
kubectl get pods -n longhorn-system
kubectl get pvc,pv -A

# Ver estado del operador de balanceo
kubectl get pods -n tailscale
kubectl get proxygroup
```
