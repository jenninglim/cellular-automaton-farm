# Cellular-automaton-farm (geoByte implementation)
**TODO**

1. Query warnings.
2. Add ability to process multiple rounds.
3. Look into LED and button functionality.


**NOTES**

* Implementation should evolve the Game of Life FOREVER!

* Button SW1:
  This button should start the reading and processing of an image, indicate reading by lighting the green LED, indicate ongoing processing by flashing of the other, separate green LED alternating its state once per processing round over the image. 

* Button SW2:
  This button should trigger the export of the current game state as a PGM image file, indicate an ongoing export by lighting the blue LED 

* Orientation Sensor:
  Use the physical X-axis tilt of the board to trigger processing to be paused, and continued once the board is horizontal again, indicate a pausing state by lighting the red LED, print a status report when pausing starts to the console containing the number of rounds processed so far, the current number of live cells and the processing time elapsed after finishing image read-in. 
