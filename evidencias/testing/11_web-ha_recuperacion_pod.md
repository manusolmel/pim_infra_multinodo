# PT-03 — Recuperación automática ante caída de pod

## Objetivo

Comprobar que Kubernetes recupera automáticamente el estado deseado de una aplicación cuando uno de sus pods es eliminado manualmente.

Esta prueba valida el comportamiento de autorrecuperación del Deployment `web-ha`: si una réplica desaparece, el controlador de Kubernetes debe crear una nueva hasta volver a tener 3 réplicas disponibles.

## Servicio evaluado

| Campo | Valor |
|---|---|
| Namespace | `testing` |
| Deployment | `web-ha` |
| Imagen | `nginx:stable-alpine` |
| Réplicas esperadas | 3 |
| Servicio asociado | `web-ha` |
| Tipo de servicio | `LoadBalancer` |

## Estado inicial

Antes de la intervención, el Deployment se encontraba en estado correcto:

```text
NAME     READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES                SELECTOR
web-ha   3/3     3            3           122m   nginx        nginx:stable-alpine   app=web-ha
```

Pods antes de la prueba:

| Pod | Estado | Nodo | IP del pod |
|---|---|---|---|
| `web-ha-69c5dcc979-k85d2` | `Running` | `debian-nodo1` | `10.233.114.133` |
| `web-ha-69c5dcc979-n4qd7` | `Running` | `debian-nodo3` | `10.233.117.189` |
| `web-ha-69c5dcc979-wzxsc` | `Running` | `debian-nodo2` | `10.233.66.132` |

## Procedimiento

Se seleccionó uno de los pods del Deployment y se eliminó manualmente:

```bash
POD=$(kubectl -n testing get pod -l app=web-ha -o jsonpath='{.items[0].metadata.name}')
kubectl -n testing delete pod "$POD"
```

Pod eliminado:

```text
web-ha-69c5dcc979-k85d2
```

Resultado de la eliminación:

```text
pod "web-ha-69c5dcc979-k85d2" deleted from testing namespace
```

A continuación se comprobó el estado del rollout:

```bash
kubectl -n testing rollout status deployment/web-ha --timeout=180s
```

Resultado:

```text
deployment "web-ha" successfully rolled out
```

## Estado final

Tras la eliminación del pod, Kubernetes creó una nueva réplica:

| Pod | Estado | Nodo | IP del pod |
|---|---|---|---|
| `web-ha-69c5dcc979-jlfh9` | `Running` | `debian-nodo1` | `10.233.114.140` |
| `web-ha-69c5dcc979-n4qd7` | `Running` | `debian-nodo3` | `10.233.117.189` |
| `web-ha-69c5dcc979-wzxsc` | `Running` | `debian-nodo2` | `10.233.66.132` |

Estado final del Deployment:

```text
NAME     READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES                SELECTOR
web-ha   3/3     3            3           123m   nginx        nginx:stable-alpine   app=web-ha
```

## Evidencia generada

La salida completa de la prueba queda registrada en:

```text
evidencias/testing/11_web-ha_recuperacion_pod.txt
```

## Resultado de la prueba

| Criterio | Resultado |
|---|---|
| Deployment parte de `3/3` réplicas | Apto |
| Pod eliminado correctamente | Apto |
| Kubernetes detecta la pérdida de réplica | Apto |
| Kubernetes crea un nuevo pod | Apto |
| Deployment vuelve a `3/3` | Apto |
| Intervención manual adicional requerida | No |

## Conclusión

La prueba confirma que Kubernetes mantiene el estado deseado del Deployment `web-ha`. Al eliminar manualmente el pod `web-ha-69c5dcc979-k85d2`, el clúster creó automáticamente una nueva réplica (`web-ha-69c5dcc979-jlfh9`) y el Deployment volvió al estado `3/3`.

Esto valida la autorrecuperación básica de las aplicaciones desplegadas en el clúster y demuestra que la disponibilidad del servicio no depende de un pod individual.
