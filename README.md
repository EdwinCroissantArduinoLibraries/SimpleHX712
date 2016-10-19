# SimpleHX712
This is a simple (maybe not so simple :) ) non blocking library for the Avia Semiconductor HX712 24-Bit Analog-to-Digital Converter (ADC) for Weight Scales.

With this library you can:

* use it in a blocking or non blocking way.
* suppress the first readings after a reset.
* check the status of the chip:
    * init: the chip is initializing and has not reached the required reads
    * valid: the last reading is valid
    * poweredDown: the chip is powered down
    * timedOut: the initializing time after powerup and reset is 400 ms when the output data rate is 10 Hz, if the chip is not ready after 500 ms it's probably disconnected   
* optionaly smooth the output by applying exponetial smoothing, the smoothing factor alpha can be between 1/256 and 255/256
* tare the output, which "resets" the output to 0, this can use the smoothed and the unsmoothed output
* calibrate the chip by adjusting the output to the desired value.  
* all the settings can be read and written to.

See the example how to use this library.

Note:
This library is tested with a HX712 in the reference configuration.
The two chips I used (marked HX712 5510192) could not be set to a gain of 256, only the rate could be changed. 
