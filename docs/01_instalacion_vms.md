# 01 — Instalación de las máquinas virtuales

## 1. Entorno de virtualización

Se utiliza **Oracle VirtualBox** como hipervisor de escritorio. Cada nodo se despliega como una VM independiente con los siguientes recursos:

| Recurso | Valor |
|---------|-------|
| RAM | 4096 MB |
| CPU | 2 vCPU |
| Disco | Dinámico (VDI) |
| Red | NAT (Tailscale se encarga de la conectividad entre nodos) |

Se crean un total de **8 máquinas virtuales**: 1 nodo de administración, 3 control-plane y 4 workers.

---

## 2. Instalación del sistema operativo

### 2.1 ISO utilizada

```
debian-13.3.0-amd64-netinst.iso
```

Debian 13 (Trixie) en su variante netinst, que descarga los paquetes durante la instalación.

### 2.2 Parámetros comunes de instalación

Todos los nodos se instalan con la misma configuración base:

| Parámetro | Valor |
|-----------|-------|
| Idioma | Español |
| País/Región | España |
| Zona horaria | Europe/Madrid |
| Teclado | Español |
| Tipo de instalación | Mínima (sin entorno gráfico) |
| Paquetes seleccionados | SSH server + herramientas básicas del sistema |

### 2.3 Usuario del sistema

Se crea el usuario `usuario1` durante la instalación. Posteriormente se añade al grupo de sudoers para poder ejecutar comandos con privilegios.

### 2.4 Hostnames asignados

| Nodo | Hostname | Rol |
|------|----------|-----|
| Admin | debian-admin | Gestión (Ansible/Kubespray) |
| Worker 1 | debian-nodo1 | Worker |
| Worker 2 | debian-nodo2 | Worker |
| Worker 3 | debian-nodo3 | Worker |
| Worker 4 | debian-nodo4 | Worker |
| Control Plane 1 | debian-nodo5 | Control-plane + etcd |
| Control Plane 2 | debian-nodo6 | Control-plane + etcd |
| Control Plane 3 | debian-nodo7 | Control-plane + etcd |

### 2.5 Paquete adicional post-instalación

En cada nodo, tras la primera sesión SSH:

```bash
sudo apt update
sudo apt install -y curl
```

---

## 3. Instalación de Tailscale

Tailscale proporciona la red privada entre todos los nodos del laboratorio. Se instala en cada una de las 8 máquinas virtuales.

### 3.1 Procedimiento por nodo

```bash
# Descargar e instalar Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Unir el nodo a la tailnet
sudo tailscale up
```

Al ejecutar `tailscale up`, aparece un enlace de autenticación:

```
To authenticate, visit:
    https://login.tailscale.com/a/<ID>
```

Se abre la URL en un navegador y se autoriza el nodo desde la cuenta de Tailscale del equipo.

### 3.2 IPs Tailscale asignadas

Cada nodo recibe una IP estable del rango `100.x.x.x` que se mantiene independientemente de la red física:

| Hostname     | IP Tailscale   |
| ------------ | -------------- |
| debian-admin | 100.109.133.56 |
| debian-nodo1 | 100.126.156.35 |
| debian-nodo2 | 100.78.239.126 |
| debian-nodo3 | 100.115.184.93 |
| debian-nodo4 | 100.87.128.22  |
| debian-nodo5 | 100.108.88.7   |
| debian-nodo6 | 100.111.213.98 |
| debian-nodo7 | 100.126.143.93 |

### 3.3 Configuración DNS de respaldo

Tailscale MagicDNS configura `100.100.100.100` como único resolver DNS en cada nodo. Esto puede causar fallos transitorios si el resolver tiene un micro-corte.

Se configuraron DNS de respaldo en la consola de administración de Tailscale (`login.tailscale.com/admin/dns` → Nameservers → Add nameserver):

| Proveedor | Dirección |
|-----------|-----------|
| Google Public DNS | 8.8.8.8 |
| Cloudflare DNS | 1.1.1.1 |
| Quad9 DNS | 9.9.9.9 |

La opción **"Override DNS servers"** se deja **desactivada**: MagicDNS sigue siendo primario para nombres internos de la tailnet, con fallback a los resolvers públicos.

### 3.4 Verificación

Desde cualquier nodo, comprobar que se puede alcanzar otro nodo por su IP Tailscale:

```bash
ping -c 3 100.109.133.56   # ping al admin desde cualquier nodo
tailscale status            # ver todos los nodos de la tailnet
```

---

## 4. Notas importantes

- **Sin entorno gráfico**: la instalación mínima reduce el consumo de recursos y la superficie de ataque.
- **Tailscale como única red de comunicación**: los nodos no necesitan estar en la misma red física. Toda la comunicación (SSH, Ansible, Kubernetes) pasa por Tailscale.
- **No pausar VMs en VirtualBox**: pausar una VM congela su reloj, lo que causa desfases horarios que rompen certificados TLS y etcd. Usar `shutdown -h now` o dejarlas corriendo.
