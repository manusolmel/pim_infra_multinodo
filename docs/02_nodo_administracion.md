# 02 — Preparación del nodo de administración

**Proyecto**: Infraestructura de Hosting Multinodo  
**Nodo**: debian-admin (100.109.133.56)  
**Fecha**: Marzo 2026

---

## 1. Función del nodo admin

El nodo `debian-admin` es la máquina desde la que se controla todo el clúster. No forma parte de Kubernetes; su único propósito es ejecutar Ansible y Kubespray contra los 7 nodos del clúster.

Mantener la herramienta de despliegue fuera del sistema desplegado permite recuperar, reconfigurar y relanzar playbooks sin depender del propio clúster, siendo esta misma replicable a través del repositorio.

---

## 2. Paquetes del sistema

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip ssh curl rsync
```

Estos paquetes cubren tres necesidades: clonar repositorios (git), ejecutar Ansible dentro de un entorno virtual (python3, venv, pip), y distribuir binarios al clúster (rsync, ssh).

---

## 3. Clave SSH para Ansible

Ansible se conecta a los nodos por SSH con clave Ed25519:

```bash
ssh-keygen -t ed25519 -C "admin-kubespray"
```

Copiar la clave pública a cada nodo del clúster:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@100.126.156.35   # nodo1
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@100.78.239.126    # nodo2
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@100.115.184.93    # nodo3
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@100.87.128.22     # nodo4
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@100.108.88.7      # nodo5
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@100.111.213.98    # nodo6
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario1@100.126.143.93    # nodo7
```

---

## 4. Instalación de Kubespray

Kubespray se clona como repositorio independiente. No se modifica.

```bash
cd ~
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
```

### 4.1 Entorno virtual de Python

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

### 4.2 Verificación

```bash
ansible --version
# ansible [core 2.18.14]
```

---

## 5. Repositorio del proyecto

El repositorio del proyecto se clona por separado. Contiene la documentación y el inventario de Kubespray (nunca los playbooks de instalación):

```bash
cd ~
git clone git@github.com:manusolmel/pim_infra_multinodo.git
```

La estructura relevante:

```
~/pim_infra_multinodo/
├── README.md
├── docs/
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
├── logs/
└── .gitignore
```

Los playbooks de Kubespray se ejecutan desde `~/kubespray`, pero apuntando al inventario del proyecto con `-i`. Esta separación permite actualizar Kubespray sin tocar la configuración propia.

---

## 6. Preparación de los nodos remotos

Desde el admin, antes de lanzar el despliegue, se preparan los nodos del clúster con Ansible ad-hoc.

### 6.1 Paquetes necesarios en todos los nodos

```bash
cd ~/kubespray
source .venv/bin/activate

ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m apt -a "name=rsync,apt-transport-https,gnupg2,ca-certificates state=present update_cache=yes" -b
```

### 6.2 Sudo sin contraseña (laboratorio)

Kubespray necesita ejecutar muchas tareas como root. Para evitar bloqueos:

```bash
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m copy -a "content='usuario1 ALL=(ALL) NOPASSWD:ALL' dest=/etc/sudoers.d/usuario1 mode=0440" -b
```

> **Nota de seguridad**: `NOPASSWD` es exclusivo del entorno de laboratorio, aconsejable para evitar errores en la instalación según la documentación de Kubespray. 

### 6.3 Hostname en `/etc/hosts`

Cada nodo necesita resolver su propio hostname para que `sudo` funcione correctamente:

```bash
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m shell -a "hostname | xargs -I{} grep -q {} /etc/hosts || hostname | xargs -I{} sh -c 'echo 127.0.1.1 {} >> /etc/hosts'" -b
```

### 6.4 Sincronización horaria

Forzar sincronización de relojes (para evitar errores con etcd y certificados TLS):

```bash
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all \
  -m shell -a "chronyc makestep && sleep 2 && date" -b
```

---

## 7. Verificación de conectividad

```bash
ansible -i ~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini all -m ping -b
```

Los 7 nodos deben responder `SUCCESS` con `"pong"`.

---

## 8. Flujo de trabajo habitual

Cada vez que se abre una sesión de trabajo en el admin:

```bash
cd ~/kubespray
source .venv/bin/activate
```

Todos los comandos de Ansible y Kubespray se ejecutan desde `~/kubespray` con el venv activo.
