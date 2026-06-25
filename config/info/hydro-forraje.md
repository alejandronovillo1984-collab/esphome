# Resumen de Implementación Lógica: Hydro-Forraje

He completado la programación del ciclo inteligente de 14 días en tu archivo `hydro-forraje.yaml`. El sistema ahora es capaz de funcionar de manera autónoma, contabilizando los días, ajustando la frecuencia de riegos, y dosificando las válvulas dinámicamente según tus requerimientos.

## ¿Qué se implementó?

1. **Variables y Memoria Permanente:**
   Se crearon variables globales (`dia_actual`, `ciclos_hoy`, y `sistema_activo`). Estas variables se guardan en la memoria flash, lo que significa que si el ESP32 se reinicia o se corta la luz, **no perderá por qué día iba ni cuántos riegos ha hecho hoy**.

2. **Sensores en Home Assistant / MQTT:**
   - **Estado Actual Ciclo (Texto):** Verás exactamente en qué etapa se encuentra (ej. "Día 4-6: Inicio Crecimiento").
   - **Día Actual (Número):** Podrás ver el día (0 al 14) e incluso forzar un cambio de día manualmente si lo necesitas.
   - **Switch Iniciar/Detener:** Un botón general para dar "Play" (arranca en Día 1) o "Stop" (vuelve al Día 0).

3. **Cerebro del Tiempo (Cron Integrado):**
   - **Cada medianoche (00:00):** Automáticamente sumará +1 al Día Actual y reseteará el contador de riegos del día a cero. Al llegar al día 15, se detiene solo.
   - **Cada minuto:** Revisa qué día es, busca la frecuencia correspondiente (ej. cada 2h, cada 1.5h) y si la hora coincide matemáticamente con un ciclo de riego, dispara las válvulas.

4. **Dosificación Precisa (Multitarea):**
   El script `ejecutar_riego` controla las válvulas de manera simultánea sin bloquear el dispositivo.
   - Calcula si es el ciclo 1 del día para activar el **Sanitizante (V2)** por 1 segundo.
   - Ajusta los tiempos de la **Válvula Principal (V1)** (5s, 7s o 10s según la etapa).
   - Ajusta los tiempos de los **Nutrientes (V3)** (0s, 2s, 4s, 5s según la etapa).

> [!WARNING]
> **Revisión de Pines Físicos Requerida**
> He asignado los pines `23`, `25` y `27` a V1, V2 y V3 de manera provisional. **Debes revisar la Sección 1 (Sustituciones) en las líneas 21 a 24 del archivo `hydro-forraje.yaml`** y cambiarlos por los números de los pines reales donde conectaste los relés en tu placa Kincony.

## ¿Cómo Probarlo?

1. En tu Home Assistant o MQTT, activa el switch **"Iniciar / Detener Ciclo Forraje"**. Verás que el día pasa a `1`.
2. Podrás cambiar manualmente el número del día. Si lo pones en `5`, verás que el estado cambia a "Inicio Crecimiento".
3. Dado que las frecuencias son cada varias horas, para hacer una prueba rápida en tiempo real puedes cambiar el reloj de Home Assistant, o temporalmente modificar en el código `hydro-forraje.yaml` (alrededor de la línea 115) los `interval_mins` de `180` a `1` (para que riegue cada 1 minuto) y verificar con tus propios ojos que los relés hagan clack en los tiempos correctos. ¡No olvides volverlo a dejar como estaba!

## Integración vía MQTT (Tópicos)

Para controlar este dispositivo desde tu aplicación web a través de MQTT, debes publicar o suscribirte a los siguientes tópicos. 

**Prefijo base:** `<dev_name>` (actualmente `"aathgrbxt40sp3x66yad"` o el que configures en `substitutions`).

### 1. Iniciar / Detener el Ciclo Completo (Switch)
- **Estado (Lectura):** `<dev_name>/switch/iniciar___detener_ciclo_forraje/state`
- **Comando (Escritura):** `<dev_name>/switch/iniciar___detener_ciclo_forraje/command`
  - *Payloads aceptados:* `ON` (Para iniciar en Día 1), `OFF` (Para detener y volver al Día 0)

### 2. Día Actual (Número / Configuración)
- **Estado (Lectura):** `<dev_name>/number/dia_actual_manual/state`
- **Comando (Escritura):** `<dev_name>/number/dia_actual_manual/command`
  - *Payloads aceptados:* Un número del `0` al `15` (ej. enviar `5` salta al día 5 directamente).

### 3. Estado Actual del Ciclo (Sensor de Texto)
- **Estado (Solo Lectura):** `<dev_name>/sensor/estado_actual_ciclo/state`
  - *Devuelve:* Strings como `"Detenido"`, `"Día 1: Hidratación / Siembra"`, `"Día 4-6: Inicio Crecimiento"`, etc.

### 4. Válvulas Físicas (Switches)
*Nota: El ciclo inteligente las controla automáticamente, pero si necesitas forzar su encendido/apagado desde tu app, puedes usar:*
- **Válvula 1 (Principal):** 
  - Estado: `<dev_name>/switch/valvula_1_principal/state`
  - Comando: `<dev_name>/switch/valvula_1_principal/command`
- **Válvula 2 (Sanitizante):** 
  - Estado: `<dev_name>/switch/valvula_2_sanitizante/state`
  - Comando: `<dev_name>/switch/valvula_2_sanitizante/command`
- **Válvula 3 (Nutrientes):** 
  - Estado: `<dev_name>/switch/valvula_3_nutrientes/state`
  - Comando: `<dev_name>/switch/valvula_3_nutrientes/command`
