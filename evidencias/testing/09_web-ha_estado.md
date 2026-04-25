# PT-01 — Estado y publicación del servicio `web-ha`

## Objetivo

Verificar que el servicio de pruebas `web-ha` está desplegado correctamente en el clúster, publicado mediante Tailscale y distribuido entre varios workers.

Esta prueba sirve como base para las pruebas posteriores de balanceo, recuperación automática, continuidad del servicio y tolerancia a fallos de la entrada privada.

## Contexto

El servicio `web-ha` se despliega en el namespace:

```text
testing
```

Se utiliza como carga HTTP ligera para validar el comportamiento del clúster sin depender de una interfaz gráfica ni de una aplicación compleja.

## Comprobaciones realizadas

| Comprobación | Resultado observado |
|---|---|
| Namespace de pruebas | `testing` activo |
| Deployment | `deployment.apps/web-ha` |
| Réplicas deseadas | 3 |
| Réplicas disponibles | 3 |
| Servicio | `service/web-ha` |
| Tipo de servicio | `LoadBalancer` |
| IP interna del servicio | `10.233.19.94` |
| IP externa Tailscale | `100.84.251.148` |
| Puerto publicado | `80:31091/TCP` |
| FQDN privado | `web-ha.mastodon-dominant.ts.net` |

## Estado de los pods

| Pod | Estado | Nodo | IP del pod |
|---|---|---|---|
| `web-ha-69c5dcc979-k85d2` | `Running` | `debian-nodo1` | `10.233.114.133` |
| `web-ha-69c5dcc979-n4qd7` | `Running` | `debian-nodo3` | `10.233.117.189` |
| `web-ha-69c5dcc979-wzxsc` | `Running` | `debian-nodo2` | `10.233.66.132` |

Los tres pods están en estado `Running` y se encuentran distribuidos entre tres workers distintos. Esto evita que el servicio dependa de un único nodo de trabajo.

## Estado del servicio

El servicio aparece publicado como `LoadBalancer`:

```text
testing   web-ha   LoadBalancer   10.233.19.94   100.84.251.148   80:31091/TCP
```

La IP externa pertenece a la red de Tailscale, por lo que el servicio queda accesible desde la Tailnet sin exposición pública directa a Internet.

## Comprobación de acceso por FQDN

Se realiza una petición HTTP al nombre privado asignado al servicio:

```bash
curl -s http://web-ha.mastodon-dominant.ts.net
```

Resultado observado:

```text
web-ha pod: web-ha-69c5dcc979-n4qd7
node: debian-nodo3
```

La respuesta confirma que:

- el FQDN privado resuelve correctamente;
- el tráfico llega al servicio publicado;
- Kubernetes enruta la petición hacia uno de los pods backend;
- la respuesta identifica el pod y nodo que han atendido la petición.

## Resultado de la prueba

| Criterio | Resultado |
|---|---|
| Servicio desplegado | Apto |
| Réplicas disponibles | Apto |
| Distribución entre workers | Apto |
| Publicación mediante Tailscale | Apto |
| Acceso por FQDN privado | Apto |
| Exposición pública directa | No aplicada |

## Conclusión

El servicio `web-ha` se encuentra correctamente desplegado y publicado. Las tres réplicas están activas y distribuidas entre `debian-nodo1`, `debian-nodo2` y `debian-nodo3`.

La prueba confirma que el clúster puede publicar un servicio HTTP mediante Tailscale Operator y que dicho servicio es accesible desde la red privada a través del FQDN `web-ha.mastodon-dominant.ts.net`.

Este servicio queda establecido como base para las siguientes pruebas de balanceo, recuperación automática y continuidad durante fallos controlados.
