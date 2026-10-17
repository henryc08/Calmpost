#include <Wire.h>
#include <DFRobot_STCC4.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <math.h>

const char DEVICE_ID[] = "bin-001";

const int MOISTURE_PIN = A0;
const int TEMPERATURE_PIN = 2;
const unsigned long SAMPLE_INTERVAL_MS = 1000;

DFRobot_STCC4_I2C* co2Sensor = nullptr;
DallasTemperature* temperatureProbe = nullptr;

bool co2Ready = false;

// Prints valid JSON: a number or null.
void printNumberOrNull(float value, bool valid, int decimals) {
  if (valid && !isnan(value) && !isinf(value)) {
    Serial.print(value, decimals);
  } else {
    Serial.print("null");
  }
}

void setup() {
  Serial.begin(115200);

  // The laptop's Serial Monitor or Python bridge opens this connection.
  while (!Serial) {
    delay(10);
  }
  delay(500);

  analogReadResolution(10);
  Wire.begin();

  // Create sensor objects after Arduino initialization.
  static DFRobot_STCC4_I2C co2(&Wire, 0x64);
  co2Sensor = &co2;

  co2Ready = co2Sensor->begin();

  if (co2Ready) {
    co2Sensor->wakeup();
    delay(10);
    co2Sensor->startMeasurement();
  }

  static OneWire oneWire(TEMPERATURE_PIN);
  static DallasTemperature probe(&oneWire);
  temperatureProbe = &probe;
  temperatureProbe->begin();

  // Allow CO2 measurements to settle before sending samples.
  delay(20000);
}

void loop() {
  unsigned long sampleStarted = millis();

  // Read moisture as a raw ADC value.
  int moistureRaw = analogRead(MOISTURE_PIN);

  // Read the waterproof temperature probe.
  temperatureProbe->requestTemperatures();
  float probeTemp = temperatureProbe->getTempCByIndex(0);

  bool probeValid =
      probeTemp != DEVICE_DISCONNECTED_C &&
      probeTemp >= -55.0 &&
      probeTemp <= 125.0;

  // Read CO2 and the board's air temperature/humidity.
  uint16_t co2Ppm = 0;
  uint16_t co2Status = 0;
  float airTemp = NAN;
  float airHumidity = NAN;
  bool co2ReadOK = false;

  if (co2Ready) {
    co2ReadOK = co2Sensor->measurement(
        &co2Ppm,
        &airTemp,
        &airHumidity,
        &co2Status
    );
  }

  // Conservatively flag measurements with a sensor error as invalid.
  bool co2Valid = co2ReadOK && co2Status == 0;

  // Output exactly one JSON object per line.
  Serial.print("{\"device_id\":\"");
  Serial.print(DEVICE_ID);
  Serial.print("\"");

  Serial.print(",\"probe_temp_c\":");
  printNumberOrNull(probeTemp, probeValid, 2);

  Serial.print(",\"moisture_raw\":");
  Serial.print(moistureRaw);

  Serial.print(",\"co2_ppm\":");
  if (co2Valid) {
    Serial.print(co2Ppm);
  } else {
    Serial.print("null");
  }

  Serial.print(",\"air_temp_c\":");
  printNumberOrNull(airTemp, co2Valid, 2);

  Serial.print(",\"air_humidity_pct\":");
  printNumberOrNull(airHumidity, co2Valid, 2);

  Serial.print(",\"co2_status\":");
  if (co2ReadOK) {
    Serial.print(co2Status);
  } else {
    Serial.print("null");
  }

  Serial.println("}");

  // Include sensor-reading time in the five-second interval.
  unsigned long elapsed = millis() - sampleStarted;
  if (elapsed < SAMPLE_INTERVAL_MS) {
    delay(SAMPLE_INTERVAL_MS - elapsed);
  }
}