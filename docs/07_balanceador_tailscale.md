# 07 — Instalación y despliegue del sistema de balanceo de carga privado

## 1. Objetivo

En esta fase se despliega la capa de publicación de servicios del clúster sobre la red privada Tailscale ya utilizada por el proyecto.

El resultado de este despliegue es una infraestructura que permite:

- publicar servicios de Kubernetes mediante `Service` de tipo `LoadBalancer`;
- asignarles un nombre DNS privado dentro de la Tailnet;
- reutilizar una misma capa de entrada para distintos servicios;
- disponer de varios proxies activos para continuidad del acceso.

---

## 2. Componentes desplegados

### 2.1 Componentes principales

El sistema de balanceo privado queda formado por los siguientes elementos:

- **Tailscale Kubernetes Operator**;
- **CRDs del operador** (`proxygroups`, `proxyclasses`, etc.);
- **IngressClass tailscale**;
- **ProxyGroup** con tres proxies activos;
- servicios `LoadBalancer` con `loadBalancerClass: tailscale`.

### 2.2 Función de cada componente

| Componente | Función |
|-----------|---------|
| `operator` | Gestiona la integración entre Kubernetes y Tailscale |
| `ProxyGroup` | Mantiene varios proxies activos para la capa de entrada |
| `Service` `LoadBalancer` | Publica un servicio del clúster en la Tailnet |
| `tailscale.com/hostname` | Define el nombre DNS privado del servicio |
| `tailscale.com/proxy-group` | Asocia el servicio al grupo de proxies HA |

### 2.3 Estructura del despliegue

La publicación de servicios queda organizada en dos niveles:

1. **Capa de entrada privada**
   - gestionada por Tailscale Operator;
   - formada por el `ProxyGroup ingress-proxies`.

2. **Servicios publicados**
   - recursos `Service` de Kubernetes;
   - expuestos con `loadBalancerClass: tailscale`.

---

## 3. Requisitos previos

Antes de desplegar el sistema de balanceo se asume lo siguiente:

- clúster Kubernetes ya operativo;
- Tailscale instalado y funcional en todos los nodos;
- acceso a la consola de administración de Tailscale;
- `kubectl` configurado en `debian-admin`.

Las comprobaciones mínimas previas son:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Todos los nodos deben aparecer en estado `Ready` y los pods del sistema en estado `Running`.

---

## 4. Preparación de Tailscale

### 4.1 Configuración de tags en la policy de Tailscale

En la consola web de Tailscale, dentro de **Access controls**, se añadió la siguiente sección al fichero de policy:

```json
"tagOwners": {
  "tag:k8s-operator": [],
  "tag:k8s": ["tag:k8s-operator"]
}
```

Esta configuración permite que el operador de Kubernetes gestione recursos etiquetados como `tag:k8s`.

### 4.2 Autoaprobación de Tailscale Services

Para permitir que los proxies del grupo de alta disponibilidad anuncien servicios dentro de la Tailnet, se añadió también:

```json
"autoApprovers": {
  "services": {
    "tag:k8s": ["tag:k8s"]
  }
}
```

### 4.3 Creación del cliente OAuth

En la consola de administración de Tailscale se creó un **OAuth client** para el operador.

Permisos concedidos:

| Recurso | Permisos |
|---------|----------|
| Services | Read + Write |
| Devices Core | Read + Write |
| Auth Keys | Read + Write |

Tag asignado al cliente OAuth:

```text
tag:k8s-operator
```

El proceso genera dos credenciales necesarias para el despliegue:

- `client_id`
- `client_secret`

---

## 5. Instalación del operador de Tailscale en Kubernetes

### 5.1 Descarga del manifiesto oficial

Para mantener coherencia con el resto del proyecto, el operador se despliega mediante **manifiesto estático + kubectl**, sin introducir Helm.

```bash
mkdir -p ~/pim_infra_multinodo/manifests/tailscale
cd ~/pim_infra_multinodo/manifests/tailscale

curl -fsSLo tailscale-operator.yaml \
  https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/manifests/operator.yaml
```

### 5.2 Inserción de credenciales OAuth

En el fichero `tailscale-operator.yaml` se sustituyeron los marcadores iniciales por las credenciales generadas previamente:

```yaml
client_id: "<CLIENT_ID>"
client_secret: "<CLIENT_SECRET>"
```

> **Importante**: este fichero contiene credenciales sensibles y no debe publicarse en un repositorio compartido sin saneado previo.

### 5.3 Aplicación del manifiesto

```bash
kubectl apply -f ~/pim_infra_multinodo/manifests/tailscale/tailscale-operator.yaml
```

### 5.4 Recursos creados

El despliegue instala, entre otros:

- namespace `tailscale`;
- RBAC del operador;
- CRDs propios de Tailscale (`proxygroups`, `proxyclasses`, etc.);
- `IngressClass tailscale`;
- `Deployment` del operador.

### 5.5 Comprobación mínima

```bash
kubectl get pods -n tailscale
kubectl get ingressclass
kubectl get crds | grep tailscale
```

Resultado esperado:

- pod `operator` en `Running`;
- `IngressClass tailscale` presente;
- CRDs del operador registrados.

---

## 6. Despliegue de la capa redundante de entrada

### 6.1 Creación del ProxyGroup

Para evitar que la exposición de servicios dependa de un único proxy, se creó un grupo de proxies en alta disponibilidad.

Fichero `proxygroup-ingress-ha.yaml`:

```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyGroup
metadata:
  name: ingress-proxies
spec:
  type: ingress
  replicas: 3
```

Aplicación:

```bash
kubectl apply -f ~/pim_infra_multinodo/manifests/tailscale/proxygroup-ingress-ha.yaml
kubectl wait proxygroup ingress-proxies --for=condition=ProxyGroupReady=true --timeout=180s
```

### 6.2 Comprobación mínima

```bash
kubectl get proxygroup
kubectl get pods -n tailscale -o wide
```

Resultado esperado:

- `ProxyGroup ingress-proxies` en estado `Ready`;
- tres pods de entrada activos:
  - `ingress-proxies-0`
  - `ingress-proxies-1`
  - `ingress-proxies-2`

---

## 7. Patrón de publicación de servicios

Una vez desplegado el operador y el `ProxyGroup`, cualquier servicio del clúster que deba publicarse dentro de la Tailnet debe seguir este patrón.

### 7.1 Service tipo LoadBalancer con Tailscale

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mi-servicio
  namespace: mi-namespace
  annotations:
    tailscale.com/proxy-group: ingress-proxies
    tailscale.com/hostname: mi-servicio
spec:
  selector:
    app: mi-servicio
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: LoadBalancer
  loadBalancerClass: tailscale
```

### 7.2 Significado de cada parte

| Campo | Función |
|------|---------|
| `type: LoadBalancer` | Solicita una entrada externa al clúster |
| `loadBalancerClass: tailscale` | Indica que Tailscale Operator implementa esa entrada |
| `tailscale.com/proxy-group` | Asocia el servicio al grupo de proxies HA |
| `tailscale.com/hostname` | Define el nombre DNS privado del servicio |

### 7.3 Aplicación

```bash
kubectl apply -f servicio-ha.yaml
kubectl wait svc mi-servicio -n mi-namespace --for=condition=TailscaleIngressSvcConfigured=true --timeout=180s
kubectl get svc mi-servicio -n mi-namespace -o yaml
```

### 7.4 Resultado esperado

En el `status` del servicio deben aparecer:

- condición `TailscaleIngressSvcConfigured=True`;
- nombre DNS privado del servicio;
- IP Tailscale asociada.

Ejemplo de salida esperada:

```yaml
status:
  conditions:
  - type: TailscaleIngressSvcConfigured
    status: "True"
  loadBalancer:
    ingress:
    - hostname: mi-servicio.<tailnet>.ts.net
      ip: 100.x.x.x
```

---

## 8. Publicación de servicios existentes

Además del despliegue de servicios nuevos, también es posible adaptar servicios ya desplegados dentro del clúster.

### 8.1 Ejemplo: exposición de Longhorn UI

El servicio `longhorn-frontend`, inicialmente `ClusterIP`, se adaptó al patrón final del balanceador mediante un parche:

```bash
kubectl patch svc longhorn-frontend -n longhorn-system --type=merge -p '
{
  "metadata": {
    "annotations": {
      "tailscale.com/proxy-group": "ingress-proxies",
      "tailscale.com/hostname": "longhorn"
    }
  },
  "spec": {
    "type": "LoadBalancer",
    "loadBalancerClass": "tailscale"
  }
}'
```

Comprobación mínima:

```bash
kubectl wait svc longhorn-frontend -n longhorn-system --for=condition=TailscaleIngressSvcConfigured=true --timeout=180s
kubectl get svc longhorn-frontend -n longhorn-system -o yaml
```

El servicio quedó accesible mediante:

```text
http://longhorn.mastodon-dominant.ts.net
```

---

## 9. Comprobaciones mínimas del sistema de balanceo

Las comprobaciones mínimas documentadas para este despliegue son las siguientes:

```bash
# Operador desplegado
kubectl get pods -n tailscale

# Grupo de proxies HA
kubectl get proxygroup
kubectl get pods -n tailscale -o wide

# Servicios publicados
kubectl get svc -A

# Estado detallado de un servicio publicado
kubectl get svc <servicio> -n <namespace> -o yaml
```

Para un servicio correctamente configurado se espera:

- operador `Running`;
- tres proxies de entrada activos;
- `Service` en modo `LoadBalancer`;
- condición `TailscaleIngressSvcConfigured=True`;
- hostname privado de acceso asignado.

---

## 10. Criterio operativo adoptado

El sistema de balanceo implantado se utiliza para publicar:

- aplicaciones web internas;
- interfaces de administración privadas;
- servicios HTTP/HTTPS accesibles desde la Tailnet.

No se considera adecuado exponer por esta vía, salvo necesidad explícita:

- bases de datos;
- servicios internos de backend;
- almacenamiento interno;
- componentes exclusivos de comunicación entre pods.

---

## 11. Resultado final

Con este despliegue, el clúster incorpora una capa de balanceo de carga de entrada privada basada en:

- **Tailscale Kubernetes Operator**;
- `Service` `LoadBalancer` con `loadBalancerClass: tailscale`;
- `ProxyGroup` con **3 proxies activos** para alta disponibilidad;
- resolución DNS privada estable dentro de la Tailnet.

Esta solución queda integrada en la infraestructura multinodo ya desplegada y se utiliza como patrón común para la publicación privada de servicios dentro de la Tailnet.
