# AGENTS.md

Guía para trabajar en este repositorio ESPHome.

## Estructura

- `config/` — configuraciones de dispositivos ESPHome (fuente de verdad del dashboard).
- `config/secrets.yaml` — credenciales Wi-Fi/red (no enviar a git).
- `config/archive/` — configs versionadas/viejos.
- `templatesWeb/` — plantillas HTML/guías de configuración web.
- `docker-compose.yaml` — servicio ESPHome (dashboard en host network).

## Git / GitHub

- Push al repo `alejandronovillo1984-collab/esphome` por HTTPS.
- Las credenciales de GitHub están en `~/.git-credentials` (helper `credential.helper store`, chmod 600). **No** guardarlas en este repo ni en AGENTS.md.

## Flasheo por USB

La placa se conecta por USB y aparece como `/dev/ttyUSB0`.

`config/forrajero.yaml` usa substitutions del dashboard (`${DEVICE_NAME}`, `${WIFI_SSID}`, `${WIFI_PASSWORD}`, `${MQTT_HOST}`, `${MQTT_PORT}`, `${MQTT_USERNAME}`, `${MQTT_PASSWORD}`). El CLI de ESPHome **no** las resuelve solo, así que **no** intentés flashear el archivo original directamente (falla con `'$' is an invalid character`).

Usá el script:

```bash
./flash_forrajero.sh                # flash a /dev/ttyUSB0
./flash_forrajero.sh /dev/ttyUSB1   # puerto custom
```

Permite override de substitutions por env vars:

```bash
DEVICE_NAME=forrajero2 MQTT_HOST=mi-broker.local ./flash_forrajero.sh
```

### Ver logs seriales después de flashear

```bash
docker run --rm --privileged -v /tmp/forrajero_flash:/config \
  --device /dev/ttyUSB0:/dev/ttyUSB0 \
  ghcr.io/esphome/esphome logs forrajero.yaml --device /dev/ttyUSB0 --reset
```

(`--reset` toggles RTS/DTR para reiniciar la placa si no responde; si quedó en bootloader, es necesario.)

## Validar config sin flashear

```bash
docker run --rm -v /var/www/docker/esphome/config:/config \
  ghcr.io/esphome/esphome config forrajero.yaml
```

Si el config usa substitutions del dashboard, pasalas antes con `sed` (igual que hace `flash_forrajero.sh`) o validá contra la copia en `/tmp/forrajero_flash/`.

## Docker

El dashboard corre con el contenedor `esphome` (ver `docker-compose.yaml`). Substitutions se editan desde la UI del dashboard (Web), no vía CLI.

## Patrones de referencia

- `config/tanque_riego.yaml` — config de ejemplo con: portal cautivo + IP estática del AP, topic prefix MQTT dinámico (MAC suffix + birth/last-will), `datetime` manual para setear fecha/hora del device (fallback NTP), backup de epoch en `globals` restaurado en `on_boot`.
- `config/forrajero.yaml` — placa **Kincony KC868-A4** (4 relés: Agua = K4/GPIO4, Sanitizante = K2/GPIO15, K1/K3 libres). Ciclo de riego de 14 días con fase por día (intervalo y segundos de agua), sanitizante 1 sola vez al día (1er ciclo), índice de intensidad (`global_indice_intensidad`, 0–10: +2s de agua y −15 min de intervalo por punto). Documentado en `templatesWeb/forrajero_guia.html`.

## OTA remoto (firmware desde la app petraka)

Único mecanismo de actualización de firmware soportado por los dispositivos IoT conectados a un broker MQTT remoto (`mqtt.petraka.com.ar`). El OTA nativo de ESPHome (puerto 3232) es solo LAN, por eso estos devices bajan el binario por HTTP.

### Contrato de tópicos

| Tópico | Dirección | Payload |
|--------|-----------|---------|
| `<prefijo>/text/ota_firmware/command` | app → device | `URL|MD5` |
| `<prefijo>/text/ota_status/state` | device → app | `descargando` / `ok` / `error: ...` |
| `<prefijo>/text_sensor/firmware_version/state` | device → app | versión del firmware (e.g. `1.0.0`) |

- `URL`: binario `.bin` accesible por HTTP(S).
- `MD5`: md5 hex (32 chars) del binario; el device lo verifica antes de flashear (requisito del componente `ota.http_request`).
- `<prefijo>` = `tanque_riego-<6 hex MAC>` o `<dev_name>-<6 hex MAC>`.

### Implementación en el YAML (ya presente en `tanque_riego.yaml` y `forrajero.yaml`)

- Plataformas OTA: `- platform: esphome` (LAN/serial) + `- platform: http_request` con `id: ota_http`.
- Componente `http_request:` (en `tanque_riego`, framework arduino, va con `verify_ssl: false`; en `forrajero`, framework esp-idf, lo soporta nativo).
- Dos entidades `text` (template, `optimistic: true`, `mode: text`):
  - `ota_firmware` — `on_value` parsea `URL|MD5`, valida, publica `ota_status` y ejecuta `ota.http_request.flash`. Los valores se guardan en los globals `ota_url`/`ota_md5` (en `on_value` no se puede pasar `x` directo a la action).
  - `ota_status` — estado que lee la app.
- `text_sensor` `firmware_version` (nombre exacto `firmware_version` para el object_id MQTT) reporta `${fw_version}` vía lambda con `update_interval`.
- En `on_boot` (priority `-100`) se publican `firmware_version` y `ota_status` = `ok`.

### Pasos para publicar un firmware

1. Editar `fw_version` en `substitutions` (o subirlo desde el módulo Firmwares de la app que gestiona el `.bin`, su `URL` y su `MD5`).
2. Compilar y flashear el dispositivo referente por USB (`esphome run` o `./flash_forrajero.sh`).
3. Subir el `.bin` generado en `config/.esphome/build/<device>/.pioenvs/<device>/firmware.bin` al módulo Firmwares (la app calcula URL + MD5).
4. Desde `/dispositivos` → "Instalar firmware" el device se actualiza solo y reporta la versión nueva.