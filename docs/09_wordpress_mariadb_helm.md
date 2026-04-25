# 09 — Despliegue de WordPress + MariaDB con Helm

## 1. Objetivo

En esta fase se completa el despliegue funcional de una aplicación real sobre el clúster: **WordPress con MariaDB**, utilizando Helm como mecanismo de instalación declarativa.

El objetivo de este despliegue es validar que la infraestructura ya implantada puede ejecutar un servicio web con estado, integrando las capas ya desplegadas en el proyecto:

- Kubernetes como orquestador de la aplicación.
- Helm como herramienta de instalación y parametrización.
- Longhorn como sistema de almacenamiento persistente redundante.
- Tailscale Kubernetes Operator como capa de publicación privada.
- ProxyGroup `ingress-proxies` como entrada de alta disponibilidad.

El resultado final es un WordPress operativo y accesible desde la Tailnet mediante:

```text
http://wordpress.mastodon-dominant.ts.net
```

---

## 2. Componentes desplegados

El despliegue se realiza mediante el chart `bitnami/wordpress`, que crea los recursos necesarios para ejecutar WordPress y MariaDB dentro del namespace `wordpress`.

### 2.1 Componentes principales

| Componente | Tipo | Función |
|-----------|------|---------|
| `wp-wordpress` | Deployment | Ejecuta la aplicación WordPress |
| `wp-mariadb` | StatefulSet | Ejecuta la base de datos MariaDB |
| `wp-wordpress` | Service | Expone WordPress dentro del clúster |
| `wp-mariadb` | Service | Expone MariaDB internamente para WordPress |
| `wp-mariadb-headless` | Service headless | Servicio interno asociado al StatefulSet |
| `wp-wordpress` | PVC | Volumen persistente de WordPress |
| `data-wp-mariadb-0` | PVC | Volumen persistente de MariaDB |
| `wp-wordpress` | Secret | Credencial de administración de WordPress |
| `wp-mariadb` | Secret | Credenciales de MariaDB |

### 2.2 Relación entre capas

El flujo operativo queda así:

```text
Helm chart
   ↓
Recursos Kubernetes
   ↓
PVCs dinámicos
   ↓
Longhorn
   ↓
Service LoadBalancer
   ↓
Tailscale Operator + ProxyGroup
```

Helm no sustituye a Kubernetes ni a Longhorn. Helm solo genera y aplica los manifiestos parametrizados. Kubernetes mantiene el estado deseado de los pods y servicios, Longhorn materializa los volúmenes persistentes y Tailscale Operator publica el servicio en la red privada.

---

## 3. Requisitos previos

Antes de desplegar WordPress + MariaDB se asume que ya existen:

- clúster Kubernetes operativo;
- `kubectl` configurado en `debian-admin`;
- Helm instalado en `debian-admin`;
- Longhorn desplegado y con `StorageClass longhorn`;
- Tailscale Operator desplegado;
- ProxyGroup `ingress-proxies` operativo;
- resolución DNS funcional dentro de la Tailnet.

Comprobaciones mínimas:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get storageclass
kubectl -n longhorn-system get nodes.longhorn.io
kubectl get proxygroup
kubectl get pods -n tailscale -o wide
```

Resultado esperado:

- nodos del clúster en estado `Ready`;
- componentes principales en estado `Running`;
- `StorageClass longhorn` presente;
- Longhorn con workers disponibles para programar réplicas;
- `ProxyGroup ingress-proxies` disponible.

---

## 4. Ficheros de configuración

La configuración del despliegue queda ubicada en:

```text
manifests/wordpress_mariadb/helm/
```

Contenido:

| Fichero | Función |
|--------|---------|
| `values.example.yaml` | Plantilla base sin contraseñas reales |
| `values-small-ha.yaml` | Ajuste de tamaño de PVC para laboratorio con Longhorn |
| `node-affinity-workers.yaml` | Afinidad de WordPress y MariaDB hacia workers concretos |
| `service-tailscale-patch.json` | Parche para publicar WordPress por Tailscale |
| `scripts/install.sh` | Instalación del release Helm |
| `scripts/publish-tailscale.sh` | Publicación del servicio por Tailscale |
| `scripts/verify.sh` | Verificación funcional del despliegue |
| `scripts/uninstall.sh` | Limpieza del despliegue |

---

## 5. Decisiones de configuración

### 5.1 Uso de Helm

Se utiliza Helm porque permite instalar WordPress y MariaDB como una unidad lógica, manteniendo la configuración separada en ficheros de valores.

Valores principales:

| Parámetro | Valor |
|----------|-------|
| Release Helm | `wp` |
| Namespace | `wordpress` |
| Chart | `bitnami/wordpress` |
| StorageClass | `longhorn` |
| Publicación externa | Tailscale `LoadBalancer` |

### 5.2 Tamaño de volúmenes

La configuración final reduce los PVC a:

| Volumen | Tamaño lógico final |
|--------|---------------------|
| WordPress | 2Gi |
| MariaDB | 2Gi |

Manteniendo tres réplicas Longhorn, el consumo físico aproximado queda en:

```text
WordPress: 2Gi × 3 = 6Gi
MariaDB:   2Gi × 3 = 6Gi
Total:            ≈12Gi
```

De esta forma se conserva redundancia sin superar la capacidad práctica disponible en los workers.

### 5.3 Replicación Longhorn

No se reduce el número de réplicas de Longhorn.

Se mantiene la política del proyecto:

```text
numberOfReplicas: 3
```

Esto permite que cada volumen tenga tres copias distribuidas entre nodos distintos, siempre que Longhorn disponga de nodos y espacio suficientes.

### 5.4 Afinidad de nodos

Durante las pruebas se limitó el despliegue de WordPress y MariaDB a los workers principales:

```text
debian-nodo1
debian-nodo2
debian-nodo3
```

La afinidad se define en:

```text
node-affinity-workers.yaml
```

Motivo:

- evitar programar la aplicación en un nodo que había presentado inestabilidad temporal;
- mantener la distribución sobre workers con Longhorn operativo;
- hacer el resultado más predecible para pruebas.

### 5.5 Publicación privada

El patrón adoptado en este proyecto para publicar servicios internos es un `Service` de tipo `LoadBalancer` gestionado por Tailscale Operator.

No se utiliza Ingress para este despliegue final.

El servicio `wp-wordpress` se adapta mediante:

```json
{
  "metadata": {
    "annotations": {
      "tailscale.com/proxy-group": "ingress-proxies",
      "tailscale.com/hostname": "wordpress"
    }
  },
  "spec": {
    "type": "LoadBalancer",
    "loadBalancerClass": "tailscale"
  }
}
```

El FQDN resultante es:

```text
wordpress.mastodon-dominant.ts.net
```

---

## 6. Preparación de valores locales

Partiendo de la plantilla:

```bash
cd ~/pim_infra_multinodo/manifests/wordpress_mariadb/helm

cp values.example.yaml values.local.yaml
```

Editar los valores sensibles:

```bash
micro values.local.yaml
```

Campos que deben sustituirse:

```yaml
wordpressPassword: "CHANGE_ME"

mariadb:
  auth:
    rootPassword: "CHANGE_ME"
    password: "CHANGE_ME"
```

El fichero `values.local.yaml` contiene secretos reales y se considera un fichero local de operación. No debe usarse como plantilla pública.

---

## 7. Instalación

Desde `debian-admin`:

```bash
cd ~/pim_infra_multinodo/manifests/wordpress_mariadb/helm

./scripts/install.sh
```

El script ejecuta la instalación del chart con:

- valores locales;
- reducción de tamaño de PVC;
- afinidad de nodos;
- espera del despliegue;
- reversión en caso de fallo mediante `--rollback-on-failure`.

Secuencia equivalente:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

kubectl create namespace wordpress --dry-run=client -o yaml | kubectl apply -f -

helm install wp bitnami/wordpress \
  --namespace wordpress \
  -f values.local.yaml \
  -f values-small-ha.yaml \
  -f node-affinity-workers.yaml \
  --wait \
  --rollback-on-failure \
  --timeout 20m
```

---

## 8. Publicación mediante Tailscale

Una vez instalado el release, el servicio `wp-wordpress` se publica en la Tailnet:

```bash
cd ~/pim_infra_multinodo/manifests/wordpress_mariadb/helm

./scripts/publish-tailscale.sh
```

El script aplica el parche definido en:

```text
service-tailscale-patch.json
```

Y espera la condición:

```text
TailscaleIngressSvcConfigured=True
```

Comprobación manual equivalente:

```bash
kubectl wait svc wp-wordpress -n wordpress \
  --for=condition=TailscaleIngressSvcConfigured=true \
  --timeout=180s

kubectl get svc wp-wordpress -n wordpress -o wide
kubectl get svc wp-wordpress -n wordpress -o yaml | sed -n '/status:/,$p'
```

Resultado observado:

```text
hostname: wordpress.mastodon-dominant.ts.net
ipMode: VIP
message: 3/3 proxy backends ready and advertising
type: TailscaleIngressSvcConfigured
status: "True"
```

---

## 9. Verificación funcional

### 9.1 Estado de Helm

```bash
helm status wp -n wordpress
```

Resultado esperado:

```text
STATUS: deployed
```

### 9.2 Pods

```bash
kubectl get pods -n wordpress -o wide
```

Resultado observado:

```text
wp-mariadb-0                    1/1 Running
wp-wordpress-xxxxxxxxxx-xxxxx   1/1 Running
```

Los pods quedaron distribuidos entre workers distintos.

### 9.3 PVC y PV

```bash
kubectl get pvc -n wordpress -o wide
kubectl get pv -o wide
```

Resultado esperado:

```text
data-wp-mariadb-0   Bound   2Gi   longhorn
wp-wordpress        Bound   2Gi   longhorn
```

### 9.4 Volúmenes Longhorn

```bash
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n longhorn-system get replicas.longhorn.io
```

Resultado observado:

- volumen de WordPress en estado `attached`;
- volumen de MariaDB en estado `attached`;
- robustez `healthy`;
- tres réplicas por volumen;
- réplicas distribuidas entre `debian-nodo1`, `debian-nodo2` y `debian-nodo3`.

### 9.5 Acceso HTTP

```bash
curl -I http://wordpress.mastodon-dominant.ts.net
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

También se validó el acceso desde navegador a:

```text
http://wordpress.mastodon-dominant.ts.net/wp-admin
```

---

## 10. Credenciales de acceso

El usuario administrativo configurado es:

```text
admin
```

La contraseña puede recuperarse desde el Secret creado por Helm:

```bash
kubectl get secret --namespace wordpress wp-wordpress \
  -o jsonpath="{.data.wordpress-password}" | base64 -d
echo
```
Para el acceso de administración del usuario final se ha configurado otro usuario administrador desde el panel de WordPress, siendo el usuario:
```bash
Administrador
```
La contraseña es proporcionada diréctamente al cliente.

---

## 11. Incidencias encontradas

### 11.1 Volúmenes demasiado grandes

Durante el primer intento, el tamaño combinado de los PVC con tres réplicas superaba la capacidad práctica disponible.

Síntoma:

- Longhorn no podía programar correctamente los volúmenes;
- aparecían errores de aprovisionamiento, adjunción o montaje.

Solución:

- reducir WordPress a 2Gi;
- reducir MariaDB a 2Gi;
- conservar `numberOfReplicas: 3`.

### 11.2 Nodo worker temporalmente inestable

Durante las pruebas, `debian-nodo4` apareció temporalmente como `NotReady` en Kubernetes y como no disponible para Longhorn.

Síntomas observados:

```text
volume is not ready for workloads
Multi-Attach error
MountDevice failed
context deadline exceeded
```

Solución operativa:

- esperar recuperación del nodo;
- verificar estado de Kubernetes;
- verificar estado de Longhorn;
- limitar el despliegue de WordPress y MariaDB a workers estables mediante `nodeAffinity`.

### 11.3 Diferencia entre Kubernetes Ready y Longhorn Schedulable

Se comprobó que un nodo puede estar disponible para Kubernetes y, aun así, no ser un destino válido para réplicas Longhorn.

Antes de desplegar cargas con PVC conviene comprobar ambas capas:

```bash
kubectl get nodes
kubectl -n longhorn-system get nodes.longhorn.io
```

---

## 12. Limpieza

Para eliminar el despliegue:

```bash
cd ~/pim_infra_multinodo/manifests/wordpress_mariadb/helm

./scripts/uninstall.sh
```

Comprobación posterior:

```bash
helm list -A
kubectl get namespace wordpress || true
kubectl get pvc -A
kubectl get pv
kubectl -n longhorn-system get volumes.longhorn.io
```

El resultado esperado tras una limpieza completa es:

- release Helm eliminado;
- namespace `wordpress` eliminado;
- PVC/PV eliminados;
- volúmenes Longhorn asociados eliminados.

---

## 13. Criterio de diseño adoptado

El despliegue final de WordPress + MariaDB se integra con el diseño general del proyecto:

1. **Aplicación real con estado**
   - WordPress representa una carga web real.
   - MariaDB introduce persistencia y dependencia de base de datos.

2. **Persistencia redundante**
   - los PVC se resuelven mediante Longhorn;
   - se mantienen tres réplicas por volumen;
   - los datos no dependen de un único worker.

3. **Publicación privada coherente**
   - el servicio se publica mediante Tailscale Operator;
   - se reutiliza el ProxyGroup `ingress-proxies`;
   - se evita exposición pública a Internet.

4. **Despliegue repetible**
   - la configuración queda separada en ficheros de valores;
   - la instalación se ejecuta mediante scripts;
   - los secretos reales quedan fuera de la plantilla base.

---

## 14. Resultado final

Con esta fase, el clúster dispone de un servicio WordPress + MariaDB operativo sobre la infraestructura multinodo.

Estado final alcanzado:

- release Helm `wp` desplegado;
- namespace `wordpress` activo;
- WordPress en `Running`;
- MariaDB en `Running`;
- PVCs creados dinámicamente con Longhorn;
- volúmenes Longhorn en estado `healthy`;
- tres réplicas por volumen;
- servicio publicado por Tailscale Operator;
- acceso funcional mediante `wordpress.mastodon-dominant.ts.net`.

Este despliegue valida que la infraestructura no solo soporta pruebas simples, sino también una aplicación web persistente publicada mediante la capa privada de entrada del proyecto.
