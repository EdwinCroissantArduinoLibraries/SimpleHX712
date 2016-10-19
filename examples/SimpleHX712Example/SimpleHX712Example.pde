#include "Arduino.h"
#include <EEPROM.h>
#include <SimpleHX712.h>


/*----Setup a SingleHX712 instance and pass our pins ----*/

SimpleHX712 scale(A0, A1);

/*----Recognizable names for the EEPROM addresses ----*/

enum EEPROMAdr {
	eeIndentifier = 0,		// two bytes for identifier use
	eeAlpha = 2,			// one byte for alpha
	eeReadsUntilValid = 3,	// one byte for amount of reads before valid date
	eeGain = 4,				// one byte for gain
	eeTare = 5,				// 4 byte for tare
	eeAdjuster = 9,			// 4 bytes for adjuster
	eeRate = 13,			// 2 bytes for the rate
};

/*----Declare variables ----*/
uint32_t LastScaleUpdate, LastPrintDot; //LastSuccessfulRead,
uint16_t UpdateRate = 1000;
char buff[80];
bool Verbose = true;

// Helper function to call a function at a certain interval

void doFunctionAtInterval(void (*callBackFunction)(), uint32_t *lastEvent,
		uint32_t Interval) {
	uint32_t now = millis();
	if ((now - *lastEvent) >= Interval) {
		*lastEvent = now;
		callBackFunction();
	}
}

// Helper functions to read and write the EEPROM

int16_t EEPROMread16(int address) {
	int16_t result;
	for (int i = 0; i < 2; ++i) {
		reinterpret_cast<uint8_t*>(&result)[i] = EEPROM.read(address + i);
	}
	return result;
}

void EEPROMupdate16(int address, int16_t value){
	for (int i = 0; i < 2; ++i) {
		EEPROM.update(address + i, reinterpret_cast<uint8_t*>(&value)[i]);
	}
}

int32_t EEPROMread32(int address) {
	int32_t result;
	for (int i = 0; i < 4; ++i) {
		reinterpret_cast<uint8_t*>(&result)[i] = EEPROM.read(address + i);
	}
	return result;
}

void EEPROMupdate32(int address, int32_t value){
	for (int i = 0; i < 4; ++i) {
		EEPROM.update(address + i, reinterpret_cast<uint8_t*>(&value)[i]);
	}
}

// Helper function to print one dot only
void printDot() {
	Serial.print(".");
}

void setup() {
	// start serial port
	Serial.begin(57600);
	Serial.print(F("\nNon blocking Simple HX711 Library Demo\n\n"));

	// read EEPROM
	if (loadFromEEPROM()) Serial.println(F("Settings loaded from EEPROM\n"));

	printSettings();

	/*
	 * start with a blocking call to read the scale :)
	 * at 10Hz the initialization time of the scale is about
	 * 400 ms, after that we take 3 readings to get stable
	 */
	Serial.print(F("\nStarting scale"));
	while (!scale.read()) {
		doFunctionAtInterval(printDot, &LastPrintDot, 50);
		yield(); //@suppress("Statement has no effect") as statement is for ESP8266
	};
	Serial.print("\n");
	printHelp();
	Serial.print(F("\nSetup finished, accepting commands...\n\n\n"));
	LastScaleUpdate = millis();
}

void loop() {
	doFunctionAtInterval(outputScale, &LastScaleUpdate, UpdateRate);
	scale.read();
	serialListen();
}

void outputScale() {
	switch (scale.getStatus()) {
	case SimpleHX712::poweredDown:
		Serial.println(F("Scale powered down"));
		break;
	case SimpleHX712::timedOut:
		Serial.println(F("Scale not connected"));
		break;
	case SimpleHX712::init:
		Serial.println(F("Scale initializing"));
		break;
	case SimpleHX712::valid:
		if (Verbose) sprintf(buff,"%10ld %10ld %10ld %10ld %10ld %10ld",
				scale.getRaw(),
				scale.getRaw(true),
				scale.getRawMinusTare(true),
				scale.getAdjusted(),
				scale.getAdjusted(true),
				scale.getAdjusted() - scale.getAdjusted(true));
		else sprintf(buff,"%10ld", scale.getAdjusted(true));
		Serial.println(buff);
	}
}

void serialListen() {
	int32_t input;
	if (Serial.available()) {
		switch (Serial.read()) {
		case 't':
			// tare: sets the output to zero
			scale.tare(true);
			Serial.println(F("Scale set to zero"));
			break;
		case 's':
			// set: s1000 adjust the output to 1000
			input = Serial.parseInt();
			if (input != 0) {
				scale.adjustTo(input, true);
				Serial.print(F("Scale adjusted to: "));
				Serial.println(input);
			}
			break;
		case 'a':
			// alpha: s128 set alpha (smoothing factor) to 128/256 = 0.5
			input = Serial.parseInt();
			if (input > 0 && input < 256) {
				scale.setAlpha(input);
				Serial.print(F("Smoothing factor set to: "));
				Serial.print(input);
				Serial.print(F(" which equals an alpha of: "));
				Serial.println((float(input) / 256), 2);
			}
			break;
		case 'r':
			// read: r10 set the amount of reads to ten after a reset
			// gain change or time to get a valid read
			input = Serial.parseInt();
			if (input > 0 && input < 256) {
				scale.setReadsUntilValid(input);
				Serial.print(F("Reads until valid: "));
				Serial.println(input);
			}
			break;
		case 'g':
			// gain: g64 set the gain to 64
			input = Serial.parseInt();
			if (input == 0)
				scale.setGain(SimpleHX712::g128r10);
			else if (input == 1)
				scale.setGain(SimpleHX712::bat);
			else if (input == 2)
				scale.setGain(SimpleHX712::g128r40);
			else if (input == 3)
				scale.setGain(SimpleHX712::g256r10);
			else if (input == 4)
				scale.setGain(SimpleHX712::g256r40);
			printGain(scale.getGain());
			break;
		case 'd':
			//power down: powers the chip down
			scale.powerDown();
			Serial.println(F("Powered down"));
			break;
		case 'u':
			// power up: powers the chip up
			scale.powerUp();
			Serial.println(F("Powered up"));
			break;
		case 'D':
			// Display rate: d1000 set the update rate to 1000 ms
			input = Serial.parseInt();
			if (input > 99 && input < 10000) {
				UpdateRate = input;
				Serial.print(F("Update rate set to: "));
				Serial.println(input);
			}
			break;
		case 'e':
			// store alpha, gain, rate, tare and adjuster in eeprom
			saveToEEPROM();
			Serial.println(F("EEPROM updated"));
			break;
		case 'p':
			// print settings
			Serial.println();
			printSettings();
			Serial.println();
			break;
		case 'v':
			// toggles verbose output
			Verbose = !Verbose;
			break;
		case 'h':
			// print the commands
			printHelp();
			break;
		}

	}
}

bool loadFromEEPROM() {
	if (EEPROMread16(eeIndentifier) == 4321) {
		scale.setAlpha(EEPROM.read(eeAlpha));
		scale.setReadsUntilValid(EEPROM.read(eeReadsUntilValid));
		scale.setGain(SimpleHX712::gain(EEPROM.read(eeGain)));
		scale.setTare(EEPROMread32(eeTare));
		scale.setAdjuster(EEPROMread32(eeAdjuster));
		UpdateRate = EEPROMread16(eeRate);
		return true;
	} else return false;
}

void saveToEEPROM() {
	EEPROMupdate16(eeIndentifier, 4321);
	EEPROM.update(eeAlpha, scale.getAlpha());
	EEPROM.update(eeReadsUntilValid, scale.getReadsUntilValid());
	EEPROM.update(eeGain, scale.getGain());
	EEPROMupdate32(eeTare, scale.getTare());
	EEPROMupdate32(eeAdjuster, scale.getAdjuster());
	EEPROMupdate16(eeRate, UpdateRate);
}

void printSettings() {
	Serial.println(F("Settings:\n"));
	Serial.print(F("Smoothing factor set to: "));
	Serial.print(scale.getAlpha());
	Serial.print(F(" which equals an alpha of: "));
	Serial.println((float(scale.getAlpha()) / 256), 2);
	Serial.print(F("Reads until valid: "));
	Serial.println(scale.getReadsUntilValid());
	printGain(scale.getGain());
	Serial.print(F("Tare set to: "));
	Serial.println(scale.getTare());
	Serial.print(F("Ajuster set to: "));
	Serial.println(scale.getAdjuster());
	Serial.print(F("Update rate set to: "));
	Serial.println(UpdateRate);
}

void printHelp() {
	Serial.println(F("\nt = tare, sets the output to zero"));
	Serial.println(F("s = set, s1000 sets the output to 1000"));
	Serial.println(F("d = power down, powers the chip down"));
	Serial.println(F("u = power up, powers the chip up"));
	Serial.println(F("e = EEPROM, store alpha, gain, rate, tare and adjuster in eeprom"));
	Serial.println(F("p = print settings"));
	Serial.println(F("v = verbose toggle, toggles between verbose and simple output"));
	Serial.println(F("D = Display rate, d1000 set the update rate to 1000 ms"));
	Serial.println(F("r = reads, r10 set the amount of reads to ten after a reset"));
	Serial.println(F("g = gain, g0 = g128r10, g1 = bat, g2 = g128r40, g3 = g256r10 and g4 = g256r40"));
	Serial.println(F("a = alpha, s128 set alpha (smoothing factor) to 128/256 = 0.5"));
	Serial.println(F("h = help, print these commands\n"));
}

void printGain(SimpleHX712::gain gain) {
	Serial.print(F("Gain set to: "));
	switch (gain) {
			case SimpleHX712::g128r10:
				Serial.println(F("128 rate 10"));
				break;
			case SimpleHX712::bat:
				Serial.println(F("battery rate 40"));
				break;
			case SimpleHX712::g128r40:
				Serial.println(F("128 rate 40"));
				break;
			case SimpleHX712::g256r10:
				Serial.println(F("256 rate 10"));
				break;
			case SimpleHX712::g256r40:
				Serial.println(F("256 rate 40"));
				break;
	};
}
