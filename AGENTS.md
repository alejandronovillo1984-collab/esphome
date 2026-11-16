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

La placa se conecta por USB (adaptador **CH341A**) y aparece como `/dev/ttyUSB0`.

Usá **siempre** el script `flasheador.sh` (nunca `esphome run` directo sobre `forrajero.yaml`):

```bash
./flasheador.sh riegoTanque              # flash tanque_riego.yaml a /dev/ttyUSB0
./flasheador.sh forrajero                # flash forrajero.yaml a /dev/ttyUSB0
./flasheador.sh cuatroRelays             # flash cuatro_relays.yaml a /dev/ttyUSB0
./flasheador.sh forrajero /dev/ttyUSB1   # puerto custom
```

`riegoTanque` = `config/tanque_riego.yaml` (substitutions fijas en el archivo). `cuatroRelays` = `config/cuatro_relays.yaml` (ESP-12F, 4 relés activos en alto, substitutions fijas). `forrajero` = `config/forrajero.yaml`, que usa substitutions del dashboard (`${DEVICE_NAME}`, `${WIFI_SSID}`, `${WIFI_PASSWORD}`, `${MQTT_HOST}`, `${MQTT_PORT}`, `${MQTT_USERNAME}`, `${MQTT_PASSWORD}`). El CLI de ESPHome **no** las resuelve solo, así que **no** intentés flashear el archivo original directamente (falla con `'$' is an invalid character`). El script resuelve las substitutions vía `sed` a una copia en `/tmp/esphome_flash_cache/<target>/`.

Permite override de substitutions por env vars:

```bash
DEVICE_NAME=forrajero2 MQTT_HOST=mi-broker.local ./flasheador.sh forrajero
```

### Ver logs seriales después de flashear

```bash
docker run --rm --privileged -v /tmp/esphome_flash_cache/forrajero:/config \
  --device /dev/ttyUSB0:/dev/ttyUSB0 \
  ghcr.io/esphome/esphome logs forrajero.yaml --device /dev/ttyUSB0 --reset
```

(`--reset` toggles RTS/DTR para reiniciar la placa si no responde; si quedó en bootloader, es necesario.)

## Validar config sin flashear

```bash
docker run --rm -v /var/www/docker/esphome/config:/config \
  ghcr.io/esphome/esphome config forrajero.yaml
```

Si el config usa substitutions del dashboard, pasalas antes con `sed` (igual que hace `flasheador.sh`) o validá contra la copia en `/tmp/esphome_flash_cache/<target>/`.

## Docker

El dashboard corre con el contenedor `esphome` (ver `docker-compose.yaml`). Substitutions se editan desde la UI del dashboard (Web), no vía CLI.

## Compilar y OTA por LAN

Para compilar sin USB y actualizar varias placas en la red (OTA nativo, puerto 3232):

```bash
docker exec esphome esphome compile tanque_riego.yaml
avahi-browse -rt _esphomelib._tcp   # lista placas: hostname .local + IP
docker exec esphome esphome upload tanque_riego.yaml --device <ip>
```

### Workaround de build (esp-idf 5.5.4)

`esphome compile` falla con `Multiple ways to build the same target ... esp_efuse_fields.c` por un bug del framework `framework-espidf` v5.5.4 de pioarduino (archivo duplicado `efuse/src/esp_efuse_fields.c` vs `efuse/esp32/esp_efuse_fields.c`). Fix (hay que reaplicarlo si se recrea el contenedor o se re-descarga el framework):

```bash
docker exec esphome sh -lc '
FW=/config/.esphome/platformio/packages/framework-espidf/components/efuse
mv "$FW/esp32/esp_efuse_fields.c" "$FW/esp32/esp_efuse_fields_soc.c"
sed -i "s/\"esp_efuse_fields.c\"/\"esp_efuse_fields_soc.c\"/" "$FW/esp32/sources.cmake"'
```

Tras un `esphome clean` es necesario recompilar entero (~10 min). **Atención:** después del OTA las placas pueden caer en modo AP (`ap_timeout: 20s`) y hay que reconectarlas por el portal cautivo.

## Patrones de referencia

- `config/tanque_riego.yaml` — config de ejemplo con: portal cautivo + IP estática del AP, topic prefix MQTT dinámico (MAC suffix + birth/last-will), `datetime` manual para setear fecha/hora del device (fallback NTP), backup de epoch en `globals` restaurado en `on_boot`, switch `forzado_manual` (override de la rutina de riego). Documentado en `templatesWeb/tanque_riego_guia.html`.
- `config/forrajero.yaml` — placa **Kincony KC868-A4** (4 relés: Agua = K4/GPIO4, Sanitizante = K2/GPIO15, K1/K3 libres). Ciclo de riego de 14 días con fase por día (intervalo y segundos de agua), sanitizante 1 sola vez al día (1er ciclo), índice de intensidad (`global_indice_intensidad`, 0–10: +2s de agua y −15 min de intervalo por punto). Documentado en `templatesWeb/forrajero_guia.html`.
- `config/cuatro_relays.yaml` — placa **ESP-12F 4 Channel Relay** (ESP8266; Relay1=GPIO16, Relay2=GPIO14, Relay3=GPIO12, Relay4=GPIO13; relés activos en alto). Cada canal tiene su propio modo (`apagado`, `manual`, los 6 planes del tanque y `germinadora`), extras, duración manual, programador, relay y botones. En modo AP el MQTT se deshabilita para liberar RAM; el captive portal queda operativo y al guardar WiFi el equipo se reinicia y conecta a la red nueva. Documentado en `templatesWeb/cuatro_relays_guia.html`.

## OTA remoto (firmware desde la app petraka)

Único mecanismo de actualización de firmware soportado por los dispositivos IoT conectados a un broker MQTT remoto (`mqtt.petraka.com.ar`). El OTA nativo de ESPHome (puerto 3232) es solo LAN, por eso estos devices bajan el binario por HTTP.

### Contrato de tópicos

| Tópico | Dirección | Payload |
|--------|-----------|---------|
| `<prefijo>/text/ota_firmware/command` | app → device | `URL|MD5` |
| `<prefijo>/text/ota_status/state` | device → app | `descargando` / `ok` / `error: ...` |
| `<prefijo>/sensor/firmware_version/state` | device → app | versión del firmware (e.g. `1.0.0`) |

- `URL`: binario `.bin` accesible por HTTP(S).
- `MD5`: md5 hex (32 chars) del binario; el device lo verifica antes de flashear (requisito del componente `ota.http_request`).
- `<prefijo>` = `tanque_riego-<6 hex MAC>`, `cuatro_relays-<6 hex MAC>` o `<dev_name>-<6 hex MAC>`.

### Control de entidades por MQTT (tanque_riego)

Los switches/números/etc. se controlan/leen con el mismo patrón `<prefijo>/<tipo>/<object_id>/<command|state>` (el `object_id` sale del `name` en snake_case). El riego forzado manual es:

| Tópico | Dirección | Payload |
|--------|-----------|---------|
| `<prefijo>/switch/tanque_riego_forzado_manual/command` | app → device | `ON` / `OFF` |
| `<prefijo>/switch/tanque_riego_forzado_manual/state` | device → app | `ON` / `OFF` |

- `forzado_manual` (switch template, `restore_mode: ALWAYS_OFF`): al encenderlo **ignora la rutina** de riego (`verificar_riego` hace `return` temprano) y **enciende la bomba** (`relay_riego`); al apagarlo, apaga la bomba y la rutina vuelve a mandar al minuto siguiente.
- `relay_riego` → `switch/tanque_riego_riego_relay/*`; `programador_activo` → `switch/tanque_riego_programador_activo/*`.

### Implementación en el YAML (ya presente en `tanque_riego.yaml`, `forrajero.yaml` y `cuatro_relays.yaml`)

- Plataformas OTA: `- platform: esphome` (LAN/serial) + `- platform: http_request` con `id: ota_http`.
- Componente `http_request:` (en `tanque_riego`, framework arduino, va con `verify_ssl: false`; en `forrajero`, framework esp-idf, lo soporta nativo).
- Dos entidades `text` (template, `optimistic: true`, `mode: text`):
  - `ota_firmware` — `on_value` parsea `URL|MD5`, valida, publica `ota_status` y ejecuta `ota.http_request.flash`. Los valores se guardan en los globals `ota_url`/`ota_md5` (en `on_value` no se puede pasar `x` directo a la action).
  - `ota_status` — estado que lee la app.
- `text_sensor` `firmware_version` (nombre exacto `firmware_version` para el object_id MQTT) reporta `${fw_version}` vía lambda con `update_interval`. En este ESPHome los `text_sensor` publican bajo `<prefijo>/sensor/.../state`.
- En `on_boot` (priority `-100`) se publican `firmware_version` y `ota_status` = `ok`.

### Pasos para publicar un firmware

1. Editar `fw_version` en `substitutions` (o subirlo desde el módulo Firmwares de la app que gestiona el `.bin`, su `URL` y su `MD5`).
2. Compilar y flashear el dispositivo referente por USB (`./flasheador.sh forrajero` o `./flasheador.sh cuatroRelays`).
3. Subir el `.bin` generado en `config/.esphome/build/<device>/.pioenvs/<device>/firmware.bin` al módulo Firmwares (la app calcula URL + MD5).
4. Desde `/dispositivos` → "Instalar firmware" el device se actualiza solo y reporta la versión nueva.