# 05 — Ficha técnica de nodos y mapa de red

**Proyecto**: Infraestructura de Hosting Multinodo  
**Fecha de validación**: 14 de marzo de 2026

---

## 1. Inventario de nodos

| # | Hostname | IP Tailscale | Rol K8s | etcd | RAM | CPU | SO |
|---|----------|-------------|---------|------|-----|-----|----|
| — | debian-admin | 100.109.133.56 | Fuera del clúster (gestión) | No | 4 GB | 2 | Debian 13.3 Trixie |
| 1 | debian-nodo1 | 100.126.156.35 | Worker | No | 4 GB | 2 | Debian 13.3 Trixie |
| 2 | debian-nodo2 | 100.78.239.126 | Worker | No | 4 GB | 2 | Debian 13.3 Trixie |
| 3 | debian-nodo3 | 100.115.184.93 | Worker | No | 4 GB | 2 | Debian 13.3 Trixie |
| 4 | debian-nodo4 | 100.87.128.22 | Worker | No | 4 GB | 2 | Debian 13.3 Trixie |
| 5 | debian-nodo5 | 100.108.88.7 | Control-plane | Sí | 4 GB | 2 | Debian 13.3 Trixie |
| 6 | debian-nodo6 | 100.111.213.98 | Control-plane | Sí | 4 GB | 2 | Debian 13.3 Trixie |
| 7 | debian-nodo7 | 100.126.143.93 | Control-plane | Sí | 4 GB | 2 | Debian 13.3 Trixie |

**Totales**: 8 VMs, 32 GB RAM, 16 vCPU.

---

## 2. Versiones del software

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
| containerd | Gestionada por Kubespray |
| Calico | Gestionada por Kubespray |
| chrony | Paquete de Debian 13 |

---

## 3. Configuración de red

### 3.1 Capa física / virtualización

Cada VM usa NAT en VirtualBox. La conectividad real entre nodos la proporciona Tailscale.

### 3.2 Capa de transporte — Tailscale

| Aspecto | Valor |
|---------|-------|
| Tipo de red | Mesh VPN (WireGuard) |
| Rango de IPs | 100.x.x.x (asignadas por Tailscale) |
| MTU efectivo | ~1280 bytes |
| DNS primario | MagicDNS (100.100.100.100) |
| DNS fallback | 8.8.8.8, 1.1.1.1, 9.9.9.9 |
| Cifrado | WireGuard (ChaCha20, Poly1305) |

### 3.3 Capa de red del clúster — Kubernetes

| Aspecto | Valor |
|---------|-------|
| CNI | Calico |
| Encapsulación | VXLAN (IPIP desactivado) |
| MTU veth pods | 1230 bytes |
| Backend | vxlan (sin BGP) |
| Subnet de Services | 10.233.0.0/18 (16.382 IPs) |
| Subnet de Pods | 10.233.64.0/18 (16.382 IPs) |
| Prefijo por nodo | /24 (254 pods por nodo) |
| kube-proxy mode | IPVS |
| DNS interno | CoreDNS + nodelocaldns (169.254.25.10) |
| Dominio del clúster | cluster.local |

### 3.4 Acceso SSH

| Aspecto          | Valor                 |
| ---------------- | --------------------- |
| Usuario          | usuario1              |
| Tipo de clave    | Ed25519               |
| Fichero de clave | ~/.ssh/id_ed25519     |
| Sudo             | NOPASSWD (despliegue) |

---

## 4. Mapa de red lógico

```
                    ┌───────────────────────────────────────┐
                    │          Tailscale Tailnet            │
                    │     VPN mesh cifrada (WireGuard)      │
                    │         IPs: 100.x.x.x                │
                    └───┬──────┬──────┬──────┬───────┬──────┘
                        │      │      │      │       │
              ┌─────────┴──┐ ┌─┴────┐ │   ┌──┴────┐ ┌┴───────┐
              │debian-admin│ │nodo5 │ │   │nodo6  │ │nodo7   │
              │ .133.56    │ │.88.7 │ │   │.213.98│ │.143.93 │
              │  Ansible   │ │ CP+  │ │   │ CP+   │ │ CP+    │
              │  Kubespray │ │ etcd │ │   │ etcd  │ │ etcd   │
              │  kubectl   │ └──────┘ │   └───────┘ └────────┘
              └────────────┘          │
                                      │
                    ┌─────────┬───────┼───────┬─────────┐
                    │         │       │       │         │
                 ┌──┴────┐ ┌──┴───┐ ┌─┴────┐ ┌┴───────┐
                 │nodo1  │ │nodo2 │ │nodo3 │ │nodo4   │
                 │.156.35│ │.239. │ │.184. │ │.128.22 │
                 │Worker │ │126   │ │93    │ │Worker  │
                 │       │ │Worker│ │Worker│ │        │
                 └───────┘ └──────┘ └──────┘ └────────┘
```

### Capas de red superpuestas

```
┌─────────────────────────────────────────────────┐
│ Red física (NAT VirtualBox / Internet)          │
│ ┌─────────────────────────────────────────────┐ │
│ │ Tailscale (WireGuard) — 100.x.x.x           │ │
│ │ ┌─────────────────────────────────────────┐ │ │
│ │ │ Calico (VXLAN) — Overlay de pods        │ │ │
│ │ │   Services: 10.233.0.0/18               │ │ │
│ │ │   Pods:     10.233.64.0/18              │ │ │
│ │ └─────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

---

## 5. Componentes del sistema por nodo

### Control-plane (nodo5, nodo6, nodo7)

Cada nodo ejecuta: kube-apiserver, kube-controller-manager, kube-scheduler, etcd, kube-proxy, calico-node, nodelocaldns.

### Workers (nodo1, nodo2, nodo3, nodo4)

Cada nodo ejecuta: kubelet, kube-proxy, calico-node, nodelocaldns, nginx-proxy (proxy HA del API server).

### Admin (debian-admin)

No forma parte del clúster. Ejecuta: Ansible, Kubespray (venv Python), kubectl, almacena `admin.conf`.

---

## 6. Pods del sistema validados

| Componente | Instancias | Tipo | Distribución |
|-----------|-----------|------|-------------|
| calico-node | 7 | DaemonSet | Uno por nodo |
| calico-kube-controllers | 1 | Deployment | Control-plane |
| kube-apiserver | 3 | Static Pod | Uno por CP |
| kube-controller-manager | 3 | Static Pod | Uno por CP |
| kube-scheduler | 3 | Static Pod | Uno por CP |
| kube-proxy | 7 | DaemonSet | Uno por nodo |
| coredns | 2 | Deployment | Gestionado por dns-autoscaler |
| dns-autoscaler | 1 | Deployment | — |
| nodelocaldns | 7 | DaemonSet | Uno por nodo |
| nginx-proxy | 4 | Static Pod | Uno por worker |
