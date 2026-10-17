/*
 * Calmpost -- ESP32 sensor node
 *
 * Emits one JSON object per sample, in the format the backend ingests:
 *
 *   {"device_id":"bin-001","probe_temp_c":25.3,"moisture_raw":412,
 *    "co2_ppm":850,"air_temp_c":24.1,"air_humidity_pct":58.2,"co2_status":0}
 *
 * The same line goes to Serial (at 115200) and, when WIFI_ENABLED, to the
 * backend over HTTP. That means either path works with no code change:
 *   - Wi-Fi: the board POSTs to /ingest itself.
 *   - USB:   set WIFI_ENABLED to false and run backend/examples/serial_bridge.py
 *            on the laptop, which reads these lines and forwards them.
 *
 * moisture_raw is deliberately the RAW ADC count, not a percentage. The
 * backend holds each bin's calibration curve, so the probe can be
 * recalibrated (and history recomputed) without reflashing.
 *
 * Wire-up (adjust pins to the build):
 *   probe temp : DS18B20 on GPIO4 (OneWire)
 *   probe wet  : capacitive moisture -> GPIO34 (ADC1)
 *   air gap    : SCD40/41 CO2+temp+humidity on I2C (GPIO21 SDA / GPIO22 SCL)
 *
 * Libraries: WiFi + HTTPClient (bundled with the ESP32 core);
 *            OneWire + DallasTemperature; Sensirion I2C SCD4x.
 */

#include <WiFi.h>
#include <HTTPClient.h>

// Wi-Fi credentials, API_BASE, DEVICE_ID and DEVICE_TOKEN live in secrets.h,
// which is gitignored. Copy secrets.h.example to secrets.h and fill it in.
#include "secrets.h"

// ---- configuration ---------------------------------------------------------

// false = print JSON to Serial only, for the serial_bridge.py path.
const bool WIFI_ENABLED = true;

const unsigned long SAMPLE_INTERVAL_MS = 5UL * 60UL * 1000UL;  // 5 minutes
const unsigned long SERIAL_BAUD        = 115200;

const int PIN_MOISTURE = 34;  // ADC1 -- ADC2 pins are unusable while Wi-Fi is on

// ---- sensor reads ----------------------------------------------------------
//
// Replace the stubs with the real libraries once the sensors are wired. Keep
// the return types: the JSON format is the contract with the backend.

int readMoistureRaw() {
  // Average several samples; the ADC is noisy next to damp compost.
  long sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogRead(PIN_MOISTURE);
    delay(5);
  }
  return (int)(sum / 16);
}

float readProbeTempC() {
  // TODO: DallasTemperature -- sensors.requestTemperatures();
  //       return sensors.getTempCByIndex(0);
  return 25.3f;
}

// The SCD4x returns CO2, temperature and humidity from one measurement, and
// a non-zero error code is reported as co2_status so the backend can mark
// the reading unreliable instead of charting a bad number.
struct AirReading {
  float co2_ppm;
  float temp_c;
  float humidity_pct;
  int   status;
};

AirReading readAir() {
  // TODO: SensirionI2CScd4x --
  //   uint16_t co2; float t, rh;
  //   uint16_t err = scd4x.readMeasurement(co2, t, rh);
  //   return {(float)co2, t, rh, (int)err};
  return {850.0f, 24.1f, 58.2f, 0};
}

// ---- payload ---------------------------------------------------------------

// Builds the JSON line. Kept in one place so Serial and HTTP can never
// disagree about the format.
void buildJson(char* out, size_t len) {
  int   moistureRaw = readMoistureRaw();
  float probeTemp   = readProbeTempC();
  AirReading air    = readAir();

  snprintf(out, len,
    "{\"device_id\":\"%s\","
     "\"probe_temp_c\":%.1f,"
     "\"moisture_raw\":%d,"
     "\"co2_ppm\":%.0f,"
     "\"air_temp_c\":%.1f,"
     "\"air_humidity_pct\":%.1f,"
     "\"co2_status\":%d}",
    DEVICE_ID, probeTemp, moistureRaw,
    air.co2_ppm, air.temp_c, air.humidity_pct, air.status);
}

// ---- networking ------------------------------------------------------------

void connectWifi() {
  if (!WIFI_ENABLED || WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("# connecting to wifi");
  // Give up after ~15s rather than blocking forever: the Serial output is
  // still useful to the bridge even with no Wi-Fi.
  for (int i = 0; i < 30 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("\n# connected, ip=");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n# wifi failed; serial output only");
  }
}

bool postJson(const char* body) {
  if (!WIFI_ENABLED || WiFi.status() != WL_CONNECTED) return false;

  String url = String(API_BASE) + "/ingest";
  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Device-Token", DEVICE_TOKEN);
  int code = http.POST((uint8_t*)body, strlen(body));

  // '#' prefixed lines are comments the bridge ignores.
  Serial.printf("# POST %s -> %d\n", url.c_str(), code);
  if (code > 0) Serial.printf("# %s\n", http.getString().c_str());
  http.end();
  return code == 200;
}

// ---- sketch ----------------------------------------------------------------

void sample() {
  char body[256];
  buildJson(body, sizeof(body));

  // Always print the sample: this is what serial_bridge.py consumes.
  Serial.println(body);
  postJson(body);
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(200);
  analogReadResolution(12);  // 0-4095, matching the raw counts the backend expects

  // TODO: sensors.begin();  scd4x.begin(Wire); scd4x.startPeriodicMeasurement();

  connectWifi();
  sample();  // one sample straight away, so a demo is not left waiting
}

void loop() {
  connectWifi();
  sample();
  delay(SAMPLE_INTERVAL_MS);
}
