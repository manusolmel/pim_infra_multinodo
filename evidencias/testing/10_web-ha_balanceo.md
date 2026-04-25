# PT-02 — Prueba de balanceo entre réplicas de `web-ha`

## Objetivo

Comprobar que el servicio `web-ha`, publicado mediante Tailscale, reparte las peticiones HTTP entre las distintas réplicas disponibles del Deployment.

Esta prueba valida que el servicio no depende de un único pod ni de un único nodo worker.

## Servicio evaluado

| Campo | Valor |
|---|---|
| Namespace | `testing` |
| Deployment | `web-ha` |
| Servicio | `web-ha` |
| Tipo de servicio | `LoadBalancer` |
| FQDN privado | `web-ha.mastodon-dominant.ts.net` |
| Número de réplicas | 3 |

## Procedimiento

Se lanzaron 20 peticiones HTTP consecutivas contra el FQDN privado del servicio:

```bash
for i in $(seq 1 20); do
  echo "---- request $i ----"
  curl -s http://web-ha.mastodon-dominant.ts.net
  sleep 1
done | tee evidencias/testing/10_web-ha_balanceo.txt
```

Cada pod devuelve su propio nombre y el nodo en el que está ejecutándose. Esto permite comprobar qué backend atiende cada petición.

## Resultado de las peticiones

| Pod que respondió | Nodo | Nº de respuestas |
|---|---|---:|
| `web-ha-69c5dcc979-k85d2` | `debian-nodo1` | 7 |
| `web-ha-69c5dcc979-n4qd7` | `debian-nodo3` | 6 |
| `web-ha-69c5dcc979-wzxsc` | `debian-nodo2` | 7 |

Resumen obtenido mediante:

```bash
grep "web-ha pod:" evidencias/testing/10_web-ha_balanceo.txt | sort | uniq -c
```

Resultado:

```text
7 web-ha pod: web-ha-69c5dcc979-k85d2
6 web-ha pod: web-ha-69c5dcc979-n4qd7
7 web-ha pod: web-ha-69c5dcc979-wzxsc
```

## Estado de los pods durante la prueba

| Pod | Estado | Nodo | IP del pod |
|---|---|---|---|
| `web-ha-69c5dcc979-k85d2` | `Running` | `debian-nodo1` | `10.233.114.133` |
| `web-ha-69c5dcc979-n4qd7` | `Running` | `debian-nodo3` | `10.233.117.189` |
| `web-ha-69c5dcc979-wzxsc` | `Running` | `debian-nodo2` | `10.233.66.132` |

Los tres pods se mantienen en estado `Running` y están distribuidos en tres workers distintos.

## Evidencia generada

La salida completa de la prueba queda registrada en:

```text
evidencias/testing/10_web-ha_balanceo.txt
```

## Resultado de la prueba

| Criterio | Resultado |
|---|---|
| El FQDN privado responde | Apto |
| Las peticiones llegan al servicio | Apto |
| Responden varias réplicas | Apto |
| Las réplicas están distribuidas en varios workers | Apto |
| El servicio evita dependencia de un único pod | Apto |

## Conclusión

La prueba confirma que el servicio `web-ha` distribuye las peticiones entre sus tres réplicas. Las 20 peticiones realizadas fueron atendidas por los tres pods disponibles, con una distribución equilibrada: 7, 6 y 7 respuestas respectivamente.

Esto demuestra que el servicio publicado mediante Tailscale y Kubernetes no depende de una única réplica y que el tráfico puede ser atendido por backends situados en distintos nodos worker.
