#include <Wire.h>
#include <DFRobot_STCC4.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// Pointers only; sensor objects are created inside setup().
DFRobot_STCC4_I2C* co2Sensor;
DallasTemperature* temperatureProbe;

bool co2Ready = false;

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(10);
  }
  delay(500);

  Serial.println("Starting sensors...");
  Serial.flush();

  Wire.begin();
  analogReadResolution(10);

  static DFRobot_STCC4_I2C co2(&Wire, 0x64);
  co2Sensor = &co2;

  co2Ready = co2Sensor->begin();
  Serial.print("CO2 detected: ");
  Serial.println(co2Ready ? "YES" : "NO");
  Serial.flush();

  if (co2Ready) {
    Serial.println("Waking CO2 sensor...");
    Serial.flush();
    co2Sensor->wakeup();
    delay(10);

    Serial.println("Starting CO2 measurements...");
    Serial.flush();
    co2Sensor->startMeasurement();
  }

  Serial.println("Starting temperature probe...");
  Serial.flush();

  static OneWire oneWire(2);
  static DallasTemperature probe(&oneWire);
  temperatureProbe = &probe;
  temperatureProbe->begin();

  Serial.print("Temperature probes detected: ");
  Serial.println(temperatureProbe->getDeviceCount());

  Serial.println("Setup complete. Allow CO2 about 20 seconds to settle.");
}

void loop() {
  Serial.println("\n--- Readings ---");
  Serial.flush();

  // Moisture: raw value, not percentage.
  Serial.print("Moisture raw: ");
  Serial.println(analogRead(A0));

  // Waterproof temperature probe.
  temperatureProbe->requestTemperatures();
  float probeTemp = temperatureProbe->getTempCByIndex(0);

  Serial.print("Probe temperature: ");
  if (probeTemp == DEVICE_DISCONNECTED_C) {
    Serial.println("NOT FOUND - check D2 and the 4.7k resistor");
  } else {
    Serial.print(probeTemp, 2);
    Serial.println(" C");
  }

  // CO2 and the CO2 board's air temperature/humidity.
  if (co2Ready) {
    uint16_t ppm = 0;
    uint16_t status = 0;
    float airTemp = 0;
    float humidity = 0;

    if (co2Sensor->measurement(
          &ppm, &airTemp, &humidity, &status)) {
      Serial.print("CO2: ");
      Serial.print(ppm);
      Serial.println(" ppm");

      Serial.print("Air temperature: ");
      Serial.print(airTemp, 2);
      Serial.println(" C");

      Serial.print("Air humidity: ");
      Serial.print(humidity, 1);
      Serial.println(" %");

      Serial.print("CO2 status (0 = normal): ");
      Serial.println(status);
    } else {
      Serial.println("CO2: read failed / not ready");
    }
  } else {
    Serial.println("CO2: not detected");
  }

  delay(2000);
}