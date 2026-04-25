# PT-04 — Continuidad HTTP durante la caída de un pod

## Objetivo

Comprobar si el servicio `web-ha` mantiene la disponibilidad HTTP mientras se elimina manualmente una de sus réplicas.

Esta prueba complementa la prueba de recuperación automática: no solo valida que Kubernetes crea un nuevo pod, sino que el servicio publicado sigue atendiendo peticiones durante la intervención.

## Servicio evaluado

| Campo | Valor |
|---|---|
| Namespace | `testing` |
| Deployment | `web-ha` |
| Servicio | `web-ha` |
| Tipo de servicio | `LoadBalancer` |
| FQDN privado | `web-ha.mastodon-dominant.ts.net` |
| Réplicas esperadas | 3 |

## Estado inicial

Antes de iniciar la prueba, el Deployment estaba en estado correcto:

```text
NAME     READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES                SELECTOR
web-ha   3/3     3            3           130m   nginx        nginx:stable-alpine   app=web-ha
```

Pods iniciales:

| Pod | Estado | Nodo | IP del pod |
|---|---|---|---|
| `web-ha-69c5dcc979-b27hp` | `Running` | `debian-nodo1` | `10.233.114.131` |
| `web-ha-69c5dcc979-n4qd7` | `Running` | `debian-nodo3` | `10.233.117.189` |
| `web-ha-69c5dcc979-wzxsc` | `Running` | `debian-nodo2` | `10.233.66.132` |

## Procedimiento

Se lanzó un bucle de 30 peticiones HTTP contra el FQDN privado del servicio:

```bash
curl -sS --max-time 3 \
  -w " HTTP_CODE=%{http_code} TIME=%{time_total}" \
  http://web-ha.mastodon-dominant.ts.net
```

Durante el bucle se eliminó manualmente uno de los pods:

```text
web-ha-69c5dcc979-b27hp
```

Resultado de la eliminación:

```text
pod "web-ha-69c5dcc979-b27hp" deleted from testing namespace
```

## Resultado HTTP observado

| Resultado | Cantidad |
|---|---:|
| Peticiones totales | 30 |
| Respuestas HTTP `200` | 28 |
| Timeouts / `HTTP_CODE=000` | 2 |

Fallos detectados:

```text
request 17: curl: (28) Connection timed out after 3001 milliseconds  HTTP_CODE=000 TIME=3.001181
request 20: curl: (28) Connection timed out after 3002 milliseconds  HTTP_CODE=000 TIME=3.002303
```

Respuestas correctas observadas durante la prueba:

```text
HTTP_CODE=200
```

Las respuestas válidas fueron atendidas por distintos pods del Deployment, incluyendo la nueva réplica creada tras la eliminación del pod inicial.

## Estado de recuperación

El rollout finalizó correctamente:

```text
deployment "web-ha" successfully rolled out
```

Estado final de pods:

| Pod | Estado | Nodo | IP del pod |
|---|---|---|---|
| `web-ha-69c5dcc979-7k94p` | `Running` | `debian-nodo1` | `10.233.114.135` |
| `web-ha-69c5dcc979-n4qd7` | `Running` | `debian-nodo3` | `10.233.117.189` |
| `web-ha-69c5dcc979-wzxsc` | `Running` | `debian-nodo2` | `10.233.66.132` |

Estado final del Deployment:

```text
NAME     READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES                SELECTOR
web-ha   3/3     3            3           131m   nginx        nginx:stable-alpine   app=web-ha
```

## Evidencia generada

La salida completa de la prueba queda registrada en:

```text
evidencias/testing/12_web-ha_continuidad_http.txt
```

## Resultado de la prueba

| Criterio | Resultado |
|---|---|
| Deployment parte de `3/3` réplicas | Apto |
| Se elimina un pod durante tráfico activo | Apto |
| Kubernetes crea una nueva réplica | Apto |
| Deployment vuelve a `3/3` | Apto |
| La mayoría de peticiones responden HTTP `200` | Apto |
| Existieron timeouts puntuales | Apto con observaciones |

## Observación sobre el entorno

La prueba se ejecuta sobre un laboratorio formado por máquinas virtuales alojadas en equipos personales, con recursos limitados y red privada mediante Tailscale. En este contexto, dos timeouts puntuales sobre treinta peticiones se consideran una degradación aceptable para laboratorio, no una caída completa del servicio.

La prueba no demuestra disponibilidad perfecta, sino continuidad operativa razonable: el servicio siguió respondiendo durante la intervención, Kubernetes recuperó la réplica eliminada y el Deployment volvió al estado esperado.

## Conclusión

La prueba confirma que el servicio `web-ha` mantiene continuidad operativa durante la caída controlada de una réplica. De 30 peticiones realizadas durante la intervención, 28 respondieron correctamente con HTTP `200` y 2 agotaron el tiempo máximo configurado de 3 segundos.

El resultado se considera **apto con observaciones**, ya que la infraestructura recuperó el estado deseado sin intervención manual y el servicio siguió disponible de forma mayoritaria durante el proceso de recreación del pod.
