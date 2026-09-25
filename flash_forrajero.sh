#!/usr/bin/env bash
# ===================================================================
# Flash forrajero.yaml a la placa conectada por USB.
#
# El archivo forrajero.yaml usa substitutions del dashboard
# (${DEVICE_NAME}, ${WIFI_SSID}, ...) que el CLI de ESPHome no
# resuelve por sí solo, por eso se genera una copia resuelta en
# /tmp/forrajero_flash/ antes de compilar/flashear.
#
# Requiere: placa conectada a /dev/ttyUSB0 (o la pasás por $1).
# ===================================================================
set -euo pipefail

DEVICE="${1:-/dev/ttyUSB0}"
CONFIG_DIR="/var/www/docker/esphome/config"
# Revisa el build de la placa esp-idf.
FLASH_DIR="/tmp/forrajero_flash"
# No borramos el dir: su .esphome/ tiene el cache de platformio (a veces root);
# el docker (root) reescribe los objetos que cambian y el resto lo reusa.
mkdir -p "$FLASH_DIR"

# Substitutions del dashboard (ajustar si cambian en el dashboard)
DEVICE_NAME="${DEVICE_NAME:-forrajero}"
WIFI_SSID="${WIFI_SSID:-redOficina}"
WIFI_PASSWORD="${WIFI_PASSWORD:-lolita11}"
MQTT_HOST="${MQTT_HOST:-mqtt.petraka.com.ar}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USERNAME="${MQTT_USERNAME:-alejandro}"
MQTT_PASSWORD="${MQTT_PASSWORD:-piteroski1984}"

if [[ ! -e "$DEVICE" ]]; then
  echo "ERROR: No existe $DEVICE. ¿Está la placa conectada?" >&2
  exit 1
fi

echo ">> Preparando config resuelta en $FLASH_DIR"

sed \
  -e "s/\${DEVICE_NAME}/$DEVICE_NAME/g" \
  -e "s/\${WIFI_SSID}/$WIFI_SSID/g" \
  -e "s/\${WIFI_PASSWORD}/$WIFI_PASSWORD/g" \
  -e "s/\${MQTT_HOST}/$MQTT_HOST/g" \
  -e "s/\${MQTT_PORT}/$MQTT_PORT/g" \
  -e "s/\${MQTT_USERNAME}/$MQTT_USERNAME/g" \
  -e "s/\${MQTT_PASSWORD}/$MQTT_PASSWORD/g" \
  "$CONFIG_DIR/forrajero.yaml" > "$FLASH_DIR/forrajero.yaml"

cp "$CONFIG_DIR/secrets.yaml" "$FLASH_DIR/secrets.yaml"

echo ">> Flasheando a $DEVICE"
docker run --rm --privileged \
  -v "$FLASH_DIR:/config" \
  --device "$DEVICE:$DEVICE" \
  ghcr.io/esphome/esphome run forrajero.yaml --device "$DEVICE" --no-logs

echo ">> Flash completado. No te olvides de confirmar el arranque:"
echo "   ./flash_forrajero.sh  (logs por USB con: esphome logs)"