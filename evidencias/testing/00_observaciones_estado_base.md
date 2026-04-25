# Observaciones del estado base

Esta carpeta recoge las evidencias técnicas generadas durante la fase de pruebas de la entrega 5 del proyecto.

El objetivo de esta primera captura es registrar el estado inicial del clúster antes de desplegar servicios adicionales de prueba.

Las evidencias incluyen:

- Estado de los nodos del clúster.
- Estado general de los pods en todos los namespaces.
- StorageClass disponible.
- Estado de Longhorn.
- Estado de Tailscale Kubernetes Operator.
- Estado del ProxyGroup de entrada privada.
- Estado de salud del kube-apiserver mediante endpoints `readyz` y `livez`.

Cualquier nodo en estado `NotReady`, `SchedulingDisabled` o cualquier reinicio reciente relevante se considera una observación del entorno de laboratorio y se tendrá en cuenta durante la interpretación de las pruebas posteriores.
