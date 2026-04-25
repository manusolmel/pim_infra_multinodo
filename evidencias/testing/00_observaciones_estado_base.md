# Observaciones del estado base

## Objetivo

Esta evidencia registra el estado inicial del clúster antes de ejecutar las pruebas funcionales de validación operativa.
Sirve como línea base para comparar el comportamiento del sistema durante las pruebas de recuperación, disponibilidad, persistencia y acceso privado.

## Contexto de captura

La captura se ha realizado desde el nodo de administración mediante `kubectl`.

## Resumen del estado del clúster

| Elemento | Estado observado |
|---|---|
| Nodos totales del clúster | 7 |
| Nodos `Ready` | 6 |
| Nodos `NotReady` | 1 |
| Control-plane | 3 nodos `Ready` |
| Workers disponibles | `debian-nodo1`, `debian-nodo2`, `debian-nodo3` |
| Worker degradado | `debian-nodo4` |
| Versión Kubernetes | `v1.35.1` |
| Sistema operativo | Debian GNU/Linux 13 (trixie) |
| Runtime de contenedores | `containerd://2.2.1` |
| Red privada de nodos | IPs internas de Tailscale `100.x.x.x` |

El plano de control se encuentra operativo en los nodos `debian-nodo5`, `debian-nodo6` y `debian-nodo7`.  
Esto permite mantener la administración del clúster aunque exista una incidencia en un worker.

## Estado de nodos

| Nodo | Rol | Estado | IP interna | Observación |
|---|---|---|---|---|
| `debian-nodo1` | Worker | `Ready` | `100.126.156.35` | Operativo |
| `debian-nodo2` | Worker | `Ready` | `100.78.239.126` | Operativo |
| `debian-nodo3` | Worker | `Ready` | `100.115.184.93` | Operativo |
| `debian-nodo4` | Worker | `NotReady,SchedulingDisabled` | `100.87.128.22` | Nodo degradado / fuera del pool de planificación |
| `debian-nodo5` | Control-plane | `Ready` | `100.108.88.7` | Operativo |
| `debian-nodo6` | Control-plane | `Ready` | `100.111.213.98` | Operativo |
| `debian-nodo7` | Control-plane | `Ready` | `100.126.143.93` | Operativo |

## Incidencia observada en `debian-nodo4`

El nodo `debian-nodo4` aparece como `NotReady,SchedulingDisabled`.  
La condición relevante es:

```text
Ready: Unknown
Reason: NodeStatusUnknown
Message: Kubelet stopped posting node status.
```

Además, las condiciones `MemoryPressure`, `DiskPressure` y `PIDPressure` también aparecen como `Unknown`, todas asociadas al mismo motivo: el kubelet dejó de publicar estado del nodo.

Esta situación se considera una incidencia conocida del entorno de laboratorio. Para las pruebas posteriores se tomará como referencia el estado de los workers sanos (`debian-nodo1`, `debian-nodo2` y `debian-nodo3`), evitando depender de `debian-nodo4` mientras permanezca degradado.

## Estado del almacenamiento

El clúster tiene Longhorn configurado como proveedor de almacenamiento persistente:

| StorageClass | Provisioner | Estado |
|---|---|---|
| `longhorn` | `driver.longhorn.io` | Clase por defecto |
| `longhorn-static` | `driver.longhorn.io` | Clase adicional disponible |

Los pods de Longhorn se encuentran en estado `Running`:

```text
30 Running
```

Esto indica que la capa de almacenamiento está desplegada y operativa en el momento de la captura.

## Estado de la entrada privada con Tailscale

El namespace `tailscale` contiene el operador y tres proxies de entrada:

| Componente | Estado | Nodo |
|---|---|---|
| `ingress-proxies-0` | `Running` | `debian-nodo2` |
| `ingress-proxies-1` | `Running` | `debian-nodo3` |
| `ingress-proxies-2` | `Running` | `debian-nodo1` |
| `operator-6866b5448f-x9wcr` | `Running` | `debian-nodo1` |

El `ProxyGroup` principal aparece disponible:

```text
ingress-proxies   ProxyGroupReady   ingress
```

Por tanto, la capa de entrada privada del clúster está activa y preparada para publicar servicios mediante Tailscale Operator.

## Salud del kube-apiserver

La API de Kubernetes responde correctamente a las comprobaciones de vida y disponibilidad:

```text
readyz check passed
livez check passed
```

Esto confirma que el clúster es administrable desde el nodo de administración en el momento de iniciar la fase de validación.

## Evidencias asociadas

Las salidas completas se almacenan en el repositorio dentro de:

```text
evidencias/testing/
```

Ficheros asociados:

| Fichero | Contenido |
|---|---|
| `00_timestamp.txt` | Fecha y hora de captura |
| `01_nodes_base.txt` | Estado de nodos |
| `02_pods_base.txt` | Estado general de pods |
| `03_storageclass_base.txt` | StorageClass disponibles |
| `04_longhorn_pods_base.txt` | Estado de Longhorn |
| `05_tailscale_pods_base.txt` | Estado de Tailscale Operator y proxies |
| `06_proxygroup_base.txt` | Estado del ProxyGroup |
| `07_apiserver_readyz.txt` | Estado `readyz` del kube-apiserver |
| `08_apiserver_livez.txt` | Estado `livez` del kube-apiserver |

## Conclusión

El clúster parte de un estado operativo suficiente para iniciar las pruebas: el plano de control está disponible, Longhorn se encuentra en ejecución, la entrada privada mediante Tailscale está preparada y el kube-apiserver responde correctamente.

La única observación relevante es el estado degradado de `debian-nodo4`, que queda registrado como incidencia del laboratorio y se tendrá en cuenta durante la ejecución e interpretación de las pruebas posteriores.
