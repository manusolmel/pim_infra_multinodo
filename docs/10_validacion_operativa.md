# 10 — Validación operativa del clúster

Esta documentación enlaza las evidencias de validación operativa.

| ID | Prueba | Evidencia documentada | Salida bruta | Script | Resultado |
| --- | --- | --- | --- | --- | --- |
| PT-00 | Estado base del clúster | [`../evidencias/testing/00_observaciones_estado_base.md`](../evidencias/testing/00_observaciones_estado_base.md) | [`../evidencias/testing/01_nodes_base.txt`](../evidencias/testing/01_nodes_base.txt) y demás `00_*` a `08_*` | [`../evidencias/scripts/00_capture_baseline.sh`](../evidencias/scripts/00_capture_baseline.sh) | Apto con observación |
| PT-01 | Estado y publicación de `web-ha` | [`../evidencias/testing/09_web-ha_estado.md`](../evidencias/testing/09_web-ha_estado.md) | No aplica | [`../evidencias/scripts/01_web_ha_state.sh`](../evidencias/scripts/01_web_ha_state.sh) | Apto |
| PT-02 | Balanceo entre réplicas | [`../evidencias/testing/10_web-ha_balanceo.md`](../evidencias/testing/10_web-ha_balanceo.md) | [`../evidencias/testing/10_web-ha_balanceo.txt`](../evidencias/testing/10_web-ha_balanceo.txt) | [`../evidencias/scripts/02_web_ha_balance.sh`](../evidencias/scripts/02_web_ha_balance.sh) | Apto |
| PT-03 | Recuperación automática de pod | [`../evidencias/testing/11_web-ha_recuperacion_pod.md`](../evidencias/testing/11_web-ha_recuperacion_pod.md) | [`../evidencias/testing/11_web-ha_recuperacion_pod.txt`](../evidencias/testing/11_web-ha_recuperacion_pod.txt) | [`../evidencias/scripts/03_web_ha_pod_recovery.sh`](../evidencias/scripts/03_web_ha_pod_recovery.sh) | Apto |
| PT-04 | Continuidad HTTP durante caída de pod | [`../evidencias/testing/12_web-ha_continuidad_http.md`](../evidencias/testing/12_web-ha_continuidad_http.md) | [`../evidencias/testing/12_web-ha_continuidad_http.txt`](../evidencias/testing/12_web-ha_continuidad_http.txt) | [`../evidencias/scripts/04_web_ha_http_continuity.sh`](../evidencias/scripts/04_web_ha_http_continuity.sh) | Apto con observaciones |
| PT-05 | Failover de proxy Tailscale | [`../evidencias/testing/13_tailscale_proxy_failover.md`](../evidencias/testing/13_tailscale_proxy_failover.md) | [`../evidencias/testing/13_tailscale_proxy_failover.txt`](../evidencias/testing/13_tailscale_proxy_failover.txt) | [`../evidencias/scripts/05_tailscale_proxy_failover.sh`](../evidencias/scripts/05_tailscale_proxy_failover.sh) | Apto con observaciones |
| PT-06 | Persistencia Longhorn | [`../evidencias/testing/14_longhorn_persistencia.md`](../evidencias/testing/14_longhorn_persistencia.md) | [`../evidencias/testing/14_longhorn_persistencia.txt`](../evidencias/testing/14_longhorn_persistencia.txt) | [`../evidencias/scripts/06_longhorn_persistence.sh`](../evidencias/scripts/06_longhorn_persistence.sh) | Apto con observaciones |

## Manifiestos de prueba

- [`../manifests/testing/longhorn-persistence-pvc.yaml`](../manifests/testing/longhorn-persistence-pvc.yaml)
- [`../manifests/testing/longhorn-persistence-writer.yaml`](../manifests/testing/longhorn-persistence-writer.yaml)
- [`../manifests/testing/longhorn-persistence-reader.yaml`](../manifests/testing/longhorn-persistence-reader.yaml)
