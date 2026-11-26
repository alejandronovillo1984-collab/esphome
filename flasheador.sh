#!/usr/bin/env bash
# ===================================================================
# Flashea configs ESPHome por USB usando un adaptador CH341A.
#
# Uso:
#   ./flasheador.sh riegoTanque [puerto]
#   ./flasheador.sh forrajero   [puerto]
#   ./flasheador.sh cuatroRelays [puerto]
#   ./flasheador.sh riegoCesped  [puerto]
#
# Parametros:
#   riegoTanque  -> config/tanque_riego.yaml  (substitutions fijas en el archivo)
#   forrajero    -> config/forrajero.yaml     (usa substitutions del dashboard,
#                  se resuelven a una copia en /tmp/forrajero_flash/)
#   cuatroRelays -> config/cuatro_relays.yaml (ESP-12F 4 reles, substitutions fijas)
#   riegoCesped  -> config/riego_cesped.yaml  (ESP32 4 zonas, substitutions fijas)
#
# El puerto por defecto es /dev/ttyUSB0 (CH341A). Se puede override por env:
#   DEVICE_NAME=forrajero2 MQTT_HOST=mi-broker.local ./flasheador.sh forrajero
# ===================================================================
set -euo pipefail

TARGET="${1:-}"
DEVICE="${2:-/dev/ttyUSB0}"
CONFIG_DIR="/var/www/docker/esphome/config"
CACHE_DIR="/tmp/esphome_flash_cache"

if [[ -z "$TARGET" ]]; then
  echo "ERROR: Falta el parametro target." >&2
  echo "Uso: $0 <riegoTanque|forrajero|cuatroRelays|riegoCesped> [puerto]" >&2
  exit 1
fi

if [[ ! -e "$DEVICE" ]]; then
  echo "ERROR: No existe $DEVICE. ¿Está el CH341A conectado?" >&2
  exit 1
fi

# Selección de config
case "$TARGET" in
  riegoTanque|riego_tanque)
    YAML="tanque_riego.yaml"
    ;;
  forrajero)
    YAML="forrajero.yaml"
    ;;
  cuatroRelays|cuatro_relays|relays4)
    YAML="cuatro_relays.yaml"
    ;;
  riegoCesped|riego_cesped|cesped)
    YAML="riego_cesped.yaml"
    ;;
  *)
    echo "ERROR: Target desconocido '$TARGET'." >&2
    echo "Uso: $0 <riegoTanque|forrajero|cuatroRelays|riegoCesped> [puerto]" >&2
    exit 1
    ;;
esac

# Dir con cache propio por target (no lo borramos: reusa el .esphome/ de platformio)
FLASH_DIR="$CACHE_DIR/$TARGET"
mkdir -p "$FLASH_DIR"

# forrajero.yaml usa substitutions del dashboard que el CLI no resuelve:
# se genera una copia resuelta como hace flash_forrajero.sh.
if [[ "$TARGET" == "forrajero" ]]; then
  DEVICE_NAME="${DEVICE_NAME:-forrajero}"
  WIFI_SSID="${WIFI_SSID:-redOficina}"
  WIFI_PASSWORD="${WIFI_PASSWORD:-lolita11}"
  MQTT_HOST="${MQTT_HOST:-mqtt.petraka.com.ar}"
  MQTT_PORT="${MQTT_PORT:-1883}"
  MQTT_USERNAME="${MQTT_USERNAME:-alejandro}"
  MQTT_PASSWORD="${MQTT_PASSWORD:-piteroski1984}"

  echo ">> Preparando config resuelta de forrajero en $FLASH_DIR"
  sed \
    -e "s/\${DEVICE_NAME}/$DEVICE_NAME/g" \
    -e "s/\${WIFI_SSID}/$WIFI_SSID/g" \
    -e "s/\${WIFI_PASSWORD}/$WIFI_PASSWORD/g" \
    -e "s/\${MQTT_HOST}/$MQTT_HOST/g" \
    -e "s/\${MQTT_PORT}/$MQTT_PORT/g" \
    -e "s/\${MQTT_USERNAME}/$MQTT_USERNAME/g" \
    -e "s/\${MQTT_PASSWORD}/$MQTT_PASSWORD/g" \
    "$CONFIG_DIR/$YAML" > "$FLASH_DIR/$YAML"
else
  echo ">> Copiando $YAML a $FLASH_DIR"
  cp "$CONFIG_DIR/$YAML" "$FLASH_DIR/$YAML"
fi

cp "$CONFIG_DIR/secrets.yaml" "$FLASH_DIR/secrets.yaml"

echo ">> Flasheando $YAML a $DEVICE (CH341A)"
docker run --rm --privileged \
  -v "$FLASH_DIR:/config" \
  --device "$DEVICE:$DEVICE" \
  ghcr.io/esphome/esphome run "$YAML" --device "$DEVICE" --no-logs

echo ">> Flash completado. Confirmá el arranque con:"
echo "   $0 $TARGET $DEVICE  (o logs por USB con: esphome logs $YAML --device $DEVICE)"