# PT-06 — Persistencia de datos con Longhorn

## Objetivo

Comprobar que un dato almacenado en un volumen persistente gestionado por Longhorn sobrevive al ciclo de vida de un pod.

La prueba valida que el almacenamiento no depende del contenedor que lo utiliza: se escribe un dato desde un pod, se elimina ese pod, se crea un segundo pod usando el mismo PVC y se comprueba que el dato sigue disponible.

## Componentes evaluados

| Componente | Valor |
|---|---|
| Namespace | `testing` |
| StorageClass | `longhorn` |
| PVC | `longhorn-persistence-test` |
| Tamaño del volumen | `1Gi` |
| Pod escritor | `longhorn-persistence-writer` |
| Pod lector | `longhorn-persistence-reader` |
| Imagen usada | `nginx:stable-alpine` |

## Procedimiento

La prueba se realizó usando comandos `kubectl exec` para evitar condiciones de carrera durante el arranque del contenedor.

Fases ejecutadas:

1. Limpieza de recursos anteriores.
2. Creación de un PVC con `storageClassName: longhorn`.
3. Creación de un pod escritor con el PVC montado en `/data`.
4. Escritura de un fichero `test.txt` en el volumen.
5. Eliminación del pod escritor.
6. Creación de un pod lector usando el mismo PVC.
7. Lectura del fichero desde el nuevo pod.
8. Comparación entre el valor escrito y el valor leído.

## Escritura inicial

El pod escritor se creó correctamente en el nodo:

```text
debian-nodo3
```

El fichero fue escrito dentro del volumen persistente:

```text
longhorn-persistence-test 2026-04-25T15:31:15+02:00
```

Estado del PVC tras la escritura:

```text
longhorn-persistence-test   Bound   pvc-5a805ac3-fc94-492d-87c1-bc6986092e2b   1Gi   RWO   longhorn
```

## Lectura tras recreación del pod

Después de eliminar el pod escritor, se creó un pod lector con el mismo PVC montado en `/data`.

El pod lector pudo listar el contenido del volumen:

```text
-rw-r--r--    1 root     root            52 Apr 25 13:31 test.txt
```

Y pudo leer el dato persistido:

```text
longhorn-persistence-test 2026-04-25T15:31:15+02:00
```

## Comparación de datos

La prueba comparó el valor esperado con el valor leído:

```text
EXPECTED=longhorn-persistence-test 2026-04-25T15:31:15+02:00
READ=longhorn-persistence-test 2026-04-25T15:31:15+02:00
RESULT: persisted data matches initial data
```

## Estado final de Longhorn

El volumen de la prueba quedó creado y asociado a Longhorn:

```text
pvc-5a805ac3-fc94-492d-87c1-bc6986092e2b   v1   attached   degraded   1073741824   debian-nodo3
```

El volumen aparece como `attached`, pero con robustez `degraded`.

## Evidencia generada

La salida completa de la prueba queda registrada en:

```text
evidencias/testing/14_longhorn_persistencia.txt
```

Los manifiestos utilizados quedan registrados en:

```text
manifests/testing/longhorn-persistence-pvc.yaml
manifests/testing/longhorn-persistence-writer.yaml
manifests/testing/longhorn-persistence-reader.yaml
```

El script de ejecución queda registrado en:

```text
evidencias/scripts/06_longhorn_persistence.sh
```

## Resultado de la prueba

| Criterio | Resultado |
|---|---|
| PVC creado con StorageClass `longhorn` | Apto |
| PVC enlazado en estado `Bound` | Apto |
| Escritura de dato en volumen | Apto |
| Eliminación del pod escritor | Apto |
| Creación de pod lector con el mismo PVC | Apto |
| Lectura del dato desde el nuevo pod | Apto |
| Coincidencia entre dato escrito y leído | Apto |
| Volumen Longhorn en estado `healthy` | Apto con observaciones |

## Observación sobre el estado `degraded`

La persistencia funcional queda validada porque el dato leído coincide exactamente con el dato escrito antes de eliminar el pod original.

No obstante, Longhorn muestra el volumen de prueba con robustez `degraded`. Esta condición se registra como observación del entorno de laboratorio, que ya presenta un worker degradado y recursos limitados. La prueba no demuestra redundancia completa del volumen, sino persistencia del dato a través de la recreación del pod.

## Conclusión

La prueba se considera **apta con observaciones**. El dato escrito en el PVC Longhorn sobrevivió a la eliminación del pod escritor y fue leído correctamente desde un pod nuevo usando el mismo volumen.

Esto confirma que el almacenamiento persistente del clúster está desacoplado del ciclo de vida de los contenedores y puede conservar datos entre recreaciones de pods.
