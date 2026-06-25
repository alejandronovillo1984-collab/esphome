#pragma once
#include <map>
#include <vector>
#include <string>
#include <algorithm>
#include <cstring>   // memcpy
#include <queue>
#include "esp_mac.h"

namespace lora_custom {

// ─────────────────────────────────────────────────────────────────────────────
// Protocolo de paquetes LoRa personalizado
//
//  Todos los paquetes comienzan con 2 bytes de "magic number":
//    MAGIC[0] = 0xAB
//    MAGIC[1] = 0xCD
//
//  Byte [2] = Tipo de paquete (CMD byte):
//
//  ── Telemetría (TX desde Compuerta, CMD = 0x01) ──────────────────────────
//   [0xAB][0xCD][0x01]
//   [lat: float 4B][lon: float 4B][bat: float 4B]
//   [food_pct: float 4B][food_cm: float 4B]
//   [gps_enabled: uint8 1B][routine_running: uint8 1B]
//   [gate_state: uint8 1B]   0=cerrada,1=abierta,2=abriendo,3=cerrando,4=rutina
//   Total = 3 + 20 + 3 = 26 bytes
//
//  ── Comandos de control (RX en Compuerta) ────────────────────────────────
//   [0xAB][0xCD][CMD][VALUE 4B]   (9 bytes total)
//
//   CMD = 0x10  → set gps_enabled     (VALUE[0]: 0=off,1=on)
//   CMD = 0x11  → set food_open_secs  (VALUE: float)
//   CMD = 0x12  → set bocina_secs     (VALUE: float)
//   CMD = 0x13  → set altura_repo     (VALUE: float)
//   CMD = 0x14  → set schedule_input  (variable long: VALUE = string bytes, no null term)
//   CMD = 0x20  → open gate           (sin VALUE)
//   CMD = 0x21  → close gate          (sin VALUE)
//   CMD = 0x22  → stop gate           (sin VALUE)
//   CMD = 0x23  → trigger feeding routine
//   CMD = 0x24  → sound horn (3s)
//   CMD = 0x30  → restart device
// ─────────────────────────────────────────────────────────────────────────────

// Magic bytes
static const uint8_t LORA_MAGIC_0 = 0xAB;
static const uint8_t LORA_MAGIC_1 = 0xCD;

// Comandos
static const uint8_t CMD_TELEMETRY       = 0x01;
static const uint8_t CMD_SET_GPS         = 0x10;
static const uint8_t CMD_SET_FOOD_SECS   = 0x11;
static const uint8_t CMD_SET_BOCINA_SECS = 0x12;
static const uint8_t CMD_SET_ALTURA_REPO = 0x13;
static const uint8_t CMD_SET_SCHEDULE    = 0x14;
static const uint8_t CMD_OPEN_GATE       = 0x20;
static const uint8_t CMD_CLOSE_GATE      = 0x21;
static const uint8_t CMD_STOP_GATE       = 0x22;
static const uint8_t CMD_FEED_ROUTINE    = 0x23;
static const uint8_t CMD_HORN_3S         = 0x24;
static const uint8_t CMD_RESTART         = 0x30;
static const uint8_t CMD_SET_DISPLAY     = 0x40;
static const uint8_t CMD_SET_POWER       = 0x41;

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de conversión float ↔ bytes (little-endian)
// ─────────────────────────────────────────────────────────────────────────────
inline void push_float(std::vector<uint8_t>& buf, float val) {
  uint8_t tmp[4];
  memcpy(tmp, &val, 4);
  buf.insert(buf.end(), tmp, tmp + 4);
}

inline float pop_float(const std::vector<uint8_t>& buf, size_t offset) {
  if (offset + 4 > buf.size()) return 0.0f;
  float val;
  memcpy(&val, buf.data() + offset, 4);
  return val;
}

// ─────────────────────────────────────────────────────────────────────────────
// Queue de transmisión de paquetes LoRa para diferir desde hilo async de MQTT
// ─────────────────────────────────────────────────────────────────────────────
static std::queue<std::vector<uint8_t>> tx_queue;
static std::mutex tx_mutex;

inline void enqueue_packet(const std::vector<uint8_t>& pkt) {
  std::lock_guard<std::mutex> lock(tx_mutex);
  tx_queue.push(pkt);
}

inline bool dequeue_packet(std::vector<uint8_t>& pkt) {
  std::lock_guard<std::mutex> lock(tx_mutex);
  if (tx_queue.empty()) return false;
  pkt = tx_queue.front();
  tx_queue.pop();
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Verifica si un paquete tiene el magic number correcto y el tamaño mínimo
// ─────────────────────────────────────────────────────────────────────────────
inline bool is_valid_packet(const std::vector<uint8_t>& x) {
  return x.size() >= 3 && x[0] == LORA_MAGIC_0 && x[1] == LORA_MAGIC_1;
}

// ─────────────────────────────────────────────────────────────────────────────
// Cache de dispositivos activos con telemetría extendida
// ─────────────────────────────────────────────────────────────────────────────
#include <mutex>

struct DeviceInfo {
  uint32_t last_seen_time;
  uint8_t type;            // 1 = Compuerta, 2 = Repetidor
  float food_pct;
  std::string routine_state;
  bool online = false;
};

inline std::map<std::string, DeviceInfo>& get_last_seen_devices() {
  static std::map<std::string, DeviceInfo> last_seen;
  return last_seen;
}

inline std::mutex& get_devices_mutex() {
  static std::mutex devices_mutex;
  return devices_mutex;
}

// ─────────────────────────────────────────────────────────────────────────────
// Cache circular de hashes para anti-looping (repetidor)
// ─────────────────────────────────────────────────────────────────────────────
inline std::vector<uint32_t>& get_repeated_hashes() {
  static std::vector<uint32_t> hashes;
  return hashes;
}

inline uint32_t calculate_hash(const std::vector<uint8_t>& packet) {
  uint32_t hash = 5381;
  for (uint8_t b : packet) {
    hash = ((hash << 5) + hash) + b;
  }
  return hash;
}

inline bool should_repeat(const std::vector<uint8_t>& packet) {
  uint32_t hash = calculate_hash(packet);
  auto& hashes = get_repeated_hashes();
  for (uint32_t h : hashes) {
    if (h == hash) return false;
  }
  hashes.push_back(hash);
  if (hashes.size() > 20) hashes.erase(hashes.begin());
  return true;
}

inline int get_seconds_to_next_feeding(int curr_h, int curr_m, int curr_s, const std::string& schedule_str) {
  if (schedule_str.empty()) return -1;
  
  std::vector<int> sched_hours;
  size_t start = 0;
  size_t end = schedule_str.find(',');
  while (true) {
    std::string token = (end == std::string::npos) ? schedule_str.substr(start) : schedule_str.substr(start, end - start);
    token.erase(std::remove_if(token.begin(), token.end(), ::isspace), token.end());
    if (!token.empty()) {
      bool is_digits = true;
      for (char c : token) {
        if (!std::isdigit(c)) {
          is_digits = false;
          break;
        }
      }
      if (is_digits) {
        int h = std::atoi(token.c_str());
        if (h >= 0 && h < 24) {
          sched_hours.push_back(h);
        }
      }
    }
    if (end == std::string::npos) break;
    start = end + 1;
    end = schedule_str.find(',', start);
  }
  
  if (sched_hours.empty()) return -1;
  
  int min_seconds = 24 * 3600;
  int current_sec_of_day = curr_h * 3600 + curr_m * 60 + curr_s;
  
  for (int h : sched_hours) {
    int sched_sec_of_day = h * 3600;
    int diff = sched_sec_of_day - current_sec_of_day;
    if (diff <= 0) {
      diff += 24 * 3600;
    }
    if (diff < min_seconds) {
      min_seconds = diff;
    }
  }
  
  return min_seconds;
}

} // namespace lora_custom
