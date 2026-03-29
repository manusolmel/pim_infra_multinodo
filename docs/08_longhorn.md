# 08 — Instalación y despliegue de almacenamiento persistente con Longhorn

## 1. Objetivo

En esta fase se despliega la capa de almacenamiento persistente del clúster mediante **Longhorn**, una solución de almacenamiento distribuido nativa de Kubernetes.

El objetivo de esta implantación es disponer de:

- volúmenes persistentes gestionados desde Kubernetes;
- replicación de datos entre varios nodos de trabajo;
- tolerancia a fallo de nodo a nivel de almacenamiento;
- aprovisionamiento dinámico mediante `PersistentVolumeClaim`;
- integración con la capa de publicación privada ya desplegada en la Tailnet.

---

## 2. Componentes desplegados

Longhorn se instala dentro del espacio de nombres `longhorn-system` y despliega varios componentes especializados.

### 2.1 Componentes principales

| Componente | Tipo | Función |
|-----------|------|---------|
| `longhorn-manager` | DaemonSet | Gestiona nodos, discos, volúmenes y planificación de réplicas |
| `longhorn-csi-plugin` | DaemonSet | Integra Longhorn con Kubernetes mediante CSI |
| `engine-image` | DaemonSet | Distribuye la imagen del motor de volúmenes a los nodos |
| `csi-attacher`, `csi-provisioner`, `csi-resizer`, `csi-snapshotter` | Deployment | Operaciones CSI de aprovisionamiento, adjunción, expansión y snapshots |
| `longhorn-driver-deployer` | Deployment | Despliegue de controladores CSI y componentes auxiliares |
| `longhorn-ui` | Deployment | Interfaz web de administración |
| `longhorn-frontend` | Service | Punto de acceso a la interfaz web |

### 2.2 Función operativa de Longhorn

Longhorn actúa como una capa de almacenamiento en bloque distribuido sobre los workers del clúster.

Cuando una aplicación solicita un `PersistentVolumeClaim`, Kubernetes delega el aprovisionamiento en el **driver CSI de Longhorn**. A partir de ahí:

1. se crea un volumen lógico;
2. Longhorn genera las réplicas configuradas;
3. cada réplica se almacena en un nodo de trabajo distinto;
4. el volumen se expone al pod consumidor como disco persistente.

De este modo, el almacenamiento deja de depender de un único nodo y pasa a distribuirse entre varios workers.

---

## 3. Requisitos previos

Antes de desplegar Longhorn se asume lo siguiente:

- clúster Kubernetes ya operativo;
- `kubectl` configurado en `debian-admin`;
- workers disponibles para alojar réplicas;
- acceso a la red privada Tailscale para la publicación de la interfaz.

Además, los nodos deben disponer de ciertos paquetes a nivel de sistema operativo para que Longhorn pueda montar volúmenes y operar correctamente.

### 3.1 Paquetes requeridos en los nodos

En este proyecto se prepararon los nodos con:

- `open-iscsi`
- `nfs-common`
- `util-linux`
- `curl`

Y se dejó activo el servicio:

- `iscsid`

---

## 4. Preparación de nodos con Ansible

Para mantener la misma línea de trabajo del proyecto, la preparación del sistema base se realiza desde `debian-admin` mediante Ansible.

```bash
cd ~/kubespray
source .venv/bin/activate
INV=~/pim_infra_multinodo/kubespray/inventory/lab/inventory.ini
```

### 4.1 Instalación de dependencias

```bash
ansible -i $INV k8s_cluster \
  -m apt -a "name=open-iscsi,nfs-common,util-linux,curl state=present update_cache=yes" -b
```

### 4.2 Activación del servicio iSCSI

```bash
ansible -i $INV k8s_cluster \
  -m systemd -a "name=iscsid enabled=true state=started" -b
```

### 4.3 Comprobación rápida

```bash
ansible -i $INV k8s_cluster -m systemd -a "name=iscsid" -b
```

La razón de esta preparación previa es que Longhorn no trabaja únicamente a nivel lógico en Kubernetes: necesita soporte del sistema anfitrión para presentar y montar dispositivos persistentes.

---

## 5. Despliegue de Longhorn en Kubernetes

Longhorn se despliega mediante el manifiesto oficial del proyecto y `kubectl`, sin introducir Helm en esta fase.

### 5.1 Aplicación del manifiesto oficial

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.0/deploy/longhorn.yaml
```

En esta implantación, el despliegue se automatizó mediante Ansible, ejecutando `kubectl apply` contra el manifiesto oficial de Longhorn v1.7.0 desde `debian-admin`.

Este manifiesto crea, entre otros recursos:

- el namespace `longhorn-system`;
- los CRDs propios de Longhorn;
- managers y componentes CSI;
- la interfaz web;
- las `StorageClass` iniciales.

### 5.2 Comprobación mínima del despliegue

```bash
kubectl get ns longhorn-system
kubectl get all -n longhorn-system
kubectl get crd | grep longhorn
```

El resultado esperado es:

- namespace `longhorn-system` activo;
- componentes principales en `Running`;
- CRDs de Longhorn registrados en el API server.

---

## 6. Configuración básica del almacenamiento

Una vez desplegado Longhorn, Kubernetes ya dispone de una clase de almacenamiento dinámica gestionada por el driver `driver.longhorn.io`.

### 6.1 StorageClass por defecto

En el estado actual del clúster, la clase `longhorn` queda definida como clase por defecto.

```bash
kubectl get storageclass
kubectl get storageclass longhorn -o yaml
```

Parámetros relevantes observados:

| Parámetro | Valor |
|-----------|-------|
| `provisioner` | `driver.longhorn.io` |
| `storageclass.kubernetes.io/is-default-class` | `true` |
| `numberOfReplicas` | `3` |
| `fsType` | `ext4` |
| `reclaimPolicy` | `Delete` |
| `volumeBindingMode` | `Immediate` |
| `allowVolumeExpansion` | `true` |
| `staleReplicaTimeout` | `30` |
| `dataLocality` | `disabled` |

Si fuera necesario forzar de nuevo esta clase como predeterminada:

```bash
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 6.2 Ruta de almacenamiento por defecto

Longhorn utiliza como ruta de datos por defecto:

```text
/var/lib/longhorn/
```

Esto significa que, en esta implantación, las réplicas se almacenan sobre el disco local de cada worker en esa ruta, en lugar de usar un dispositivo dedicado adicional.

### 6.3 Política de replicación adoptada

La política configurada para el aprovisionamiento dinámico es de **3 réplicas por volumen**.

Esto implica que cada volumen creado intenta mantener tres copias distribuidas entre nodos de almacenamiento distintos. El efecto buscado es que la pérdida de un nodo no implique pérdida inmediata del dato, ya que las demás copias siguen disponibles para reconstrucción y reatachado.

---

## 7. Nodos de almacenamiento detectados

Longhorn registró como nodos de almacenamiento los **cuatro workers** del clúster:

- `debian-nodo1`
- `debian-nodo2`
- `debian-nodo3`
- `debian-nodo4`

Comprobación:

```bash
kubectl get nodes.longhorn.io -n longhorn-system
```

Esto confirma una decisión de diseño importante del proyecto: el almacenamiento persistente queda alojado en los **workers**, manteniendo separado el plano de control (`debian-nodo5`, `debian-nodo6`, `debian-nodo7`) de la capa de datos de las aplicaciones.

---

## 8. Exposición de la interfaz web

La interfaz de administración de Longhorn no se deja como `ClusterIP` puro. En este proyecto se integra con la capa de entrada privada ya documentada en `07_balanceador_tailscale.md`.

### 8.1 Patrón adoptado

El servicio `longhorn-frontend` se publica como:

- `type: LoadBalancer`
- `loadBalancerClass: tailscale`
- `tailscale.com/proxy-group: ingress-proxies`
- `tailscale.com/hostname: longhorn`

Comprobación:

```bash
kubectl get svc longhorn-frontend -n longhorn-system -o yaml
kubectl describe svc longhorn-frontend -n longhorn-system
```

### 8.2 Resultado

La interfaz queda accesible dentro de la Tailnet mediante:

```text
http://longhorn.mastodon-dominant.ts.net
```

Este enfoque evita exponer la UI a Internet pública y reutiliza la misma capa privada de entrada del proyecto.

---

## 9. Verificación funcional del aprovisionamiento

Para validar que Longhorn no solo está instalado, sino que además aprovisiona almacenamiento real, se comprobó la existencia de una PVC asociada al despliegue de WordPress.

### 9.1 PVC y PV creados

Comprobación:

```bash
kubectl get pvc,pv -A
```

Resultado observado:

- `PersistentVolumeClaim`: `wordpress/wordpress-pvc`
- capacidad solicitada: `5Gi`
- `StorageClass`: `longhorn`
- estado: `Bound`

Esto confirma que Kubernetes pudo resolver una petición de almacenamiento persistente a través de Longhorn y materializarla como `PersistentVolume` dinámico.

### 9.2 Volumen y réplicas generadas

Comprobaciones:

```bash
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system -o wide
kubectl get engines.longhorn.io -n longhorn-system -o wide
```

En la evidencia recogida para la PVC de WordPress se observa:

- un volumen Longhorn de `5Gi` asociado a la PVC;
- **3 réplicas** creadas;
- distribución de las réplicas entre `debian-nodo1`, `debian-nodo2` y `debian-nodo3`.

Esto encaja con la configuración declarada en la `StorageClass`: el volumen necesita tres copias y Longhorn las distribuye entre nodos distintos para evitar concentrar el riesgo en un único host.

### 9.3 Sobre el estado `detached`

En la captura de verificación, el volumen aparece en estado `detached` y las réplicas en estado `stopped`. Esto no implica un fallo de aprovisionamiento.

La causa es que el volumen solo permanece `attached` mientras existe un pod consumidor activo utilizando esa PVC. Si el pod deja de usar el volumen, Longhorn puede desacoplarlo y dejar preparadas las réplicas para un futuro reatachado.

---

## 10. Comprobaciones mínimas recomendadas

Las comprobaciones mínimas documentadas para esta fase son:

```bash
# Estado general de Longhorn
kubectl get all -n longhorn-system
kubectl get crd | grep longhorn

# Nodos de almacenamiento
kubectl get nodes.longhorn.io -n longhorn-system

# Clases de almacenamiento
kubectl get storageclass
kubectl describe storageclass longhorn

# Volúmenes y réplicas
kubectl get pvc,pv -A
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system -o wide

# Interfaz web publicada en la Tailnet
kubectl get svc longhorn-frontend -n longhorn-system -o yaml
```

Para considerar la implantación correctamente operativa debe cumplirse, como mínimo:

- `longhorn-system` desplegado;
- `StorageClass longhorn` presente y como clase por defecto;
- nodos workers registrados por Longhorn;
- PVC capaz de resolver a un PV real;
- réplicas creadas según la política configurada;
- UI accesible dentro de la Tailnet.

---

## 11. Criterio de diseño adoptado

La elección de Longhorn frente a un almacenamiento local simple responde a tres razones principales:

1. **Persistencia integrada en Kubernetes**
   - las aplicaciones consumen almacenamiento mediante PVCs estándar;
   - no dependen de rutas manuales ni montajes ad hoc por nodo.

2. **Replicación entre workers**
   - el dato no queda anclado a una única VM;
   - Longhorn puede reconstruir réplicas cuando recupera capacidad.

3. **Operación coherente con el resto del proyecto**
   - despliegue declarativo con manifiesto oficial;
   - gestión por `kubectl`;
   - automatización desde Ansible;
   - integración con la capa privada de publicación sobre Tailscale.

---

## 12. Resultado final

Con esta fase, el clúster incorpora una capa de almacenamiento persistente distribuido basada en **Longhorn v1.7.0**, integrada en el clúster Kubernetes ya desplegado.

El resultado operativo es el siguiente:

- Longhorn queda desplegado en `longhorn-system`;
- la clase `longhorn` actúa como `StorageClass` por defecto;
- los volúmenes se aprovisionan dinámicamente con **3 réplicas**;
- la ruta de datos por defecto queda en `/var/lib/longhorn/` sobre los workers;
- la interfaz web queda publicada de forma privada en la Tailnet mediante el balanceador ya implantado;
- el despliegue de WordPress ya puede consumir almacenamiento persistente sobre esta capa.

Longhorn pasa así a ser la base de persistencia del laboratorio y el componente que permite evolucionar desde pruebas efímeras hacia servicios reales con estado.
