/*
 * Calmpost -- ESP32 sensor node
 *
 * Posts one JSON sample per interval to the backend's /v1/ingest endpoint.
 * Only the backend holds the database credentials; the board holds a device
 * token, which can be revoked by re-registering the device.
 *
 * Wire-up (adjust pins to the build):
 *   top layer    : capacitive soil moisture -> GPIO34 (ADC), DS18B20 -> GPIO4
 *   bottom layer : capacitive soil moisture -> GPIO35 (ADC), DS18B20 -> GPIO4 (same bus)
 *   air gap      : CO2 sensor (MH-Z19 / SCD40) on UART2 or I2C
 *
 * Libraries: WiFi, HTTPClient (both bundled with the ESP32 core).
 */

#include <WiFi.h>
#include <HTTPClient.h>

// ---- configuration ---------------------------------------------------------
const char* WIFI_SSID     = "YOUR_WIFI";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Backend base URL. Use the LAN address of the laptop running uvicorn during
// development, e.g. http://192.168.1.42:8000
const char* API_BASE      = "http://192.168.1.42:8000";
const char* DEVICE_ID     = "bin-01";
const char* DEVICE_TOKEN  = "PASTE_TOKEN_FROM_init_db";

const unsigned long SAMPLE_INTERVAL_MS = 5UL * 60UL * 1000UL;  // 5 minutes

// ADC pins for the two moisture probes.
const int PIN_MOISTURE_TOP    = 34;
const int PIN_MOISTURE_BOTTOM = 35;

// Calibration for the capacitive probes: raw ADC in air (dry) and in water.
// Measure these once per probe -- they vary between units.
const int MOISTURE_RAW_DRY = 3200;
const int MOISTURE_RAW_WET = 1300;

// ---- helpers ---------------------------------------------------------------

float readMoisturePct(int pin) {
  // Average a few samples; the ADC is noisy next to damp compost.
  long sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogRead(pin);
    delay(5);
  }
  float raw = sum / 16.0f;
  float pct = 100.0f * (MOISTURE_RAW_DRY - raw) / (float)(MOISTURE_RAW_DRY - MOISTURE_RAW_WET);
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return pct;
}

// Replace these two with the real sensor libraries once wired.
float readTemperatureC(int whichLayer) {
  return whichLayer == 0 ? 38.0f : 22.0f;  // 0 = top, 1 = bottom
}

float readCo2Ppm() {
  return 1800.0f;
}

void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("connecting to wifi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.print("\nconnected, ip=");
  Serial.println(WiFi.localIP());
}

bool postSample() {
  // The server stamps the time on arrival, so the board needs no clock.
  char body[512];
  snprintf(body, sizeof(body),
    "{\"device_id\":\"%s\",\"zones\":["
      "{\"zone\":\"top\",\"moisture_pct\":%.1f,\"temperature_c\":%.1f},"
      "{\"zone\":\"bottom\",\"moisture_pct\":%.1f,\"temperature_c\":%.1f},"
      "{\"zone\":\"airgap\",\"co2_ppm\":%.0f}"
    "]}",
    DEVICE_ID,
    readMoisturePct(PIN_MOISTURE_TOP), readTemperatureC(0),
    readMoisturePct(PIN_MOISTURE_BOTTOM), readTemperatureC(1),
    readCo2Ppm());

  String url = String(API_BASE) + "/v1/ingest";
  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Device-Token", DEVICE_TOKEN);
  int code = http.POST((uint8_t*)body, strlen(body));

  Serial.printf("POST %s -> %d\n", url.c_str(), code);
  if (code > 0) Serial.println(http.getString());
  http.end();
  return code == 200;
}

// ---- sketch ----------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  delay(200);
  analogReadResolution(12);
  connectWifi();
  postSample();  // one sample straight away, so the demo is not waiting
}

void loop() {
  connectWifi();
  postSample();
  delay(SAMPLE_INTERVAL_MS);
}
