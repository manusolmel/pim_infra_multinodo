# PT-05 — Tolerancia de entrada privada ante caída de proxy Tailscale

## Objetivo

Comprobar que el servicio `web-ha` sigue siendo accesible mediante su FQDN privado aunque se elimine manualmente uno de los pods del `ProxyGroup` de Tailscale.

Esta prueba valida la alta disponibilidad de la capa de entrada privada del clúster.

## Componentes evaluados

| Componente | Valor |
|---|---|
| Namespace de entrada | `tailscale` |
| ProxyGroup | `ingress-proxies` |
| Servicio publicado | `web-ha` |
| Namespace del servicio | `testing` |
| Tipo de servicio | `LoadBalancer` |
| FQDN privado | `web-ha.mastodon-dominant.ts.net` |
| IP Tailscale del servicio | `100.84.251.148` |

## Estado inicial de Tailscale

Antes de la intervención, el namespace `tailscale` contenía tres proxies activos y el operador:

| Pod | Estado | Nodo |
|---|---|---|
| `ingress-proxies-0` | `Running` | `debian-nodo2` |
| `ingress-proxies-1` | `Running` | `debian-nodo3` |
| `ingress-proxies-2` | `Running` | `debian-nodo1` |
| `operator-6866b5448f-x9wcr` | `Running` | `debian-nodo1` |

El `ProxyGroup` estaba disponible:

```text
ingress-proxies   ProxyGroupReady   ingress
```

## Estado inicial del servicio `web-ha`

| Recurso | Estado |
|---|---|
| Servicio | `web-ha` |
| Tipo | `LoadBalancer` |
| Cluster IP | `10.233.19.94` |
| External IP | `100.84.251.148` |
| Puerto | `80:31091/TCP` |

Pods backend:

| Pod | Estado | Nodo |
|---|---|---|
| `web-ha-69c5dcc979-7k94p` | `Running` | `debian-nodo1` |
| `web-ha-69c5dcc979-n4qd7` | `Running` | `debian-nodo3` |
| `web-ha-69c5dcc979-wzxsc` | `Running` | `debian-nodo2` |

## Procedimiento

Se lanzó un bucle de 30 peticiones HTTP contra el FQDN privado:

```bash
curl -sS --max-time 3 \
  -w " HTTP_CODE=%{http_code} TIME=%{time_total}" \
  http://web-ha.mastodon-dominant.ts.net
```

Durante el bucle se eliminó uno de los proxies de entrada:

```bash
kubectl -n tailscale delete pod ingress-proxies-0
```

Resultado:

```text
pod "ingress-proxies-0" deleted from tailscale namespace
```

Después se esperó la recuperación del `ProxyGroup`:

```bash
kubectl wait proxygroup ingress-proxies \
  --for=condition=ProxyGroupReady=true \
  --timeout=180s
```

Resultado:

```text
proxygroup.tailscale.com/ingress-proxies condition met
```

## Resultado HTTP observado

Durante la prueba se registraron las peticiones al servicio publicado.

| Resultado | Cantidad |
|---|---:|
| Respuestas HTTP `200` durante el bucle | 29 |
| Timeouts / `HTTP_CODE=000` durante el bucle | 1 |
| Comprobación final HTTP `200` | 1 |

Resumen total registrado en la evidencia:

```text
1 HTTP_CODE=000
30 HTTP_CODE=200
```

Fallo puntual detectado:

```text
request 25: curl: (28) Connection timed out after 3004 milliseconds  HTTP_CODE=000 TIME=3.004045
```

## Estado final de Tailscale

Tras la eliminación, el pod `ingress-proxies-0` fue recreado automáticamente:

| Pod | Estado | Nodo |
|---|---|---|
| `ingress-proxies-0` | `Running` | `debian-nodo2` |
| `ingress-proxies-1` | `Running` | `debian-nodo3` |
| `ingress-proxies-2` | `Running` | `debian-nodo1` |
| `operator-6866b5448f-x9wcr` | `Running` | `debian-nodo1` |

El `ProxyGroup` volvió a estado correcto:

```text
ingress-proxies   ProxyGroupReady   ingress
```

## Comprobación final del servicio

Tras la recuperación del proxy, se realizó una petición final al FQDN privado:

```text
web-ha pod: web-ha-69c5dcc979-wzxsc
node: debian-nodo2
HTTP_CODE=200 TIME=0.191112
```

## Evidencia generada

La salida completa de la prueba queda registrada en:

```text
evidencias/testing/13_tailscale_proxy_failover.txt
```

El script usado para reproducir esta prueba queda registrado en:

```text
evidencias/scripts/05_tailscale_proxy_failover.sh
```

## Resultado de la prueba

| Criterio | Resultado |
|---|---|
| ProxyGroup parte de estado `ProxyGroupReady` | Apto |
| Servicio `web-ha` responde antes de la intervención | Apto |
| Se elimina un proxy de entrada durante tráfico activo | Apto |
| El servicio sigue respondiendo mayoritariamente | Apto |
| El proxy eliminado se recrea automáticamente | Apto |
| El ProxyGroup vuelve a estado `ProxyGroupReady` | Apto |
| Comprobación final del FQDN devuelve HTTP `200` | Apto |
| Existió un timeout puntual | Apto con observaciones |

## Observación sobre el entorno

La prueba se ejecuta en un laboratorio con máquinas virtuales sobre equipos personales y conectividad privada mediante Tailscale. En este contexto, un timeout puntual sobre el conjunto de peticiones no se interpreta como caída completa de la capa de entrada, sino como una degradación temporal aceptable durante la sustitución del proxy.

## Conclusión

La prueba confirma que la entrada privada basada en Tailscale Operator y `ProxyGroup` tolera la eliminación de uno de sus proxies. Durante la intervención, el servicio `web-ha` siguió respondiendo mayoritariamente mediante su FQDN privado y, al finalizar, el proxy eliminado fue recreado y el `ProxyGroup` volvió a estado `ProxyGroupReady`.

El resultado se considera **apto con observaciones** debido a un timeout puntual durante la prueba.
