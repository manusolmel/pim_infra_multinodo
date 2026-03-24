# Infraestructura de Hosting Multinodo

Proyecto fin de ciclo ASIR; diseño, despliegue y operación de una infraestructura distribuida de hosting con alta disponibilidad, como solución escalable y robusta para diferentes servicios en una red privada.

El proyecto se define como una plataforma de hosting multinodo orientada a PYMEs, basada en Kubernetes sobre Debian 13, con red privada Tailscale y despliegue automatizado con Kubespray/Ansible. 

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

| Capa                            | Tecnología              |
| ------------------------------- | ----------------------- |
| Virtualización                  | Oracle VirtualBox       |
| Sistema operativo               | Debian 13.3 (Trixie)    |
| Red privada entre nodos         | Tailscale (WireGuard)   |
| Automatización y despliegue     | Ansible + Kubespray     |
| Orquestación de contenedores    | Kubernetes v1.35.1      |
| Red del clúster (CNI)           | Calico                  |
| Encapsulación de red entre pods | VXLAN                   |
| Runtime de contenedores         | containerd              |
| Balanceo interno de Services    | kube-proxy en modo IPVS |
| DNS interno del clúster         | CoreDNS + nodelocaldns  |
| Sincronización horaria          | chrony                  |

### Ampliaciones previstas

> Pendiente de implementación:
>
> - StorageClass (Longhorn o local-path-provisioner)
> - WordPress + MariaDB con persistencia
> - Ingress Controller (Nginx Ingress + MetalLB)
> - Prometheus + Grafana
> - Network Policies con Calico



## Documentación

| Documento                                                       | Descripción                                                                          |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| [01 — Instalación de VMs](docs/01_instalacion_vms.md)           | Creación de VMs en VirtualBox, instalación de Debian 13 y configuración de Tailscale |
| [02 — Nodo de administración](docs/02_nodo_administracion.md)   | Preparación del admin: Ansible, Kubespray, claves SSH, preparación de nodos remotos  |
| [03 — Despliegue de Kubespray](docs/03_despliegue_kubespray.md) | Configuración, ejecución, verificación, incidencias y decisiones técnicas            |
| [04 — Referencia de comandos](docs/04_comandos.md)              | Comandos de despliegue y comandos operativos del día a día                           |
| [05 — Ficha técnica y red](docs/05_ficha_tecnica_red.md)        | Inventario de nodos, versiones de software, configuración de red y mapa              |
| [06 — Guía paso a paso](docs/06_guia_paso_a_paso.md)            | Checklist completa para reproducir el despliegue desde cero                          |
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
│   └── 07_proximos_pasos.md
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
├── logs/                              ← Logs de despliegue (excluidos de git)
└── .gitignore
```

Kubespray se clona como repositorio independiente (`~/kubespray`) y no se modifica. Los playbooks se ejecutan desde allí apuntando al inventario de este repositorio con `-i`.

## Estado actual

- [x] Laboratorio multinodo sobre 8 VMs
- [x] Clúster Kubernetes funcional (3 CP + 4 workers)
- [x] Red privada Tailscale operativa
- [x] Despliegue automatizado con Kubespray
- [x] Verificación funcional (nginx ×4 réplicas)
- [x] Documentación técnica del despliegue

## Próximos pasos

- [ ] StorageClass (Longhorn o local-path-provisioner)
- [ ] WordPress + MariaDB con persistencia
- [ ] Ingress Controller (Nginx Ingress + MetalLB)
- [ ] Pruebas de alta disponibilidad (caída de pod, worker, escalado, rolling update)
- [ ] Prometheus + Grafana
- [ ] Network Policies con Calico


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
```
