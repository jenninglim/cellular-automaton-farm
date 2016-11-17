// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <math.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width
#define NumberOfWorkers 1         //number of workers
#define uintArrayWidth 1             //ceil(IMWD - 1 / 31) + 1

// Port to access xCORE-200 buttons.
in port buttons = XS1_PORT_4E;
// Buttons signals.
#define SW2 13     // SW2 button signal.
#define SW1 14     // SW1 button signal.

// Port to access xCore-200 LEDs.
out port leds = XS1_PORT_4F;
// LED signals.
#define OFF  0     // Signal to turn the LED off.
#define GRNS 1     // Signal to turn the separate green LED on.
#define BLU  2     // Signal to turn the blue LED on.
#define GRN  4     // Signal to turn the green LED on.
#define RED  8     // Signal to turn the red LED on.

// Interface ports to orientation
port p_scl = XS1_PORT_1E;
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

typedef unsigned char uchar;      //using uchar as shorthand


/////////////////////////////////////////////////////////////////////////////////////////
//
// DISPLAYS an LED pattern
//
/////////////////////////////////////////////////////////////////////////////////////////
int showLEDs(out port p, chanend fromDist) {
    int pattern; // 1st bit (1) ...separate green LED
               // 2nd bit (2) ...blue LED
               // 3rd bit (4) ...green LED
               // 4th bit (8) ...red LED
    while (1) {
        fromDist :> pattern;   // Receive new pattern from distributor.
        p <: pattern;          // Send pattern to LED port.
    }
    return 0;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// READ BUTTONS and send button pattern to distributor.
//
/////////////////////////////////////////////////////////////////////////////////////////
void buttonListener(in port b, chanend c_toDist) {
    int r;  // Received button signal.
    while (1) {
        b when pinseq(15)  :> r;     // Check that no button is pressed.
        b when pinsneq(15) :> r;     // Check if some buttons are pressed.
        if (r == SW1 || r == SW2) {  // If either button is pressed
            c_toDist <: r;           // send button pattern to distributor.
        }
    }
}


//Returns a bit in a unint32_t integer
uchar returnBitInt(uint32_t queriedInt, uchar index) {
    if ( (queriedInt & 0x00000001 << (31 - index)) == 0 ) {
        return 0;
    }
    else {
        return 255;
    }
}

//for debug
void printBinary(uint32_t queriedInt, uchar length) {
    for (int i = 0; i < length; i ++) {
        if ( (queriedInt & 0x00000001 << (30 - i)) == 0 ) {
            printf("0 ");
        }
        else {
            printf("1 ");
        }
    }
    printf("\n");
}

/* Compresses the array of char.
 * Input: array of uchar of length 32
 * Output: Uint32 isomorphic to the array
 */
uint32_t bytesToBits(uchar line[], uchar length) {
    uint32_t output = 0;
    for (int i = 0; i < length; i ++) {
        if (line[i] == 255) {
            output = output | 0x00000001 << (31 - i);
        }
    }
    return output;
}

/* ad hoc concatentation to uint32 obselete
 * Input:
 *      head: addeds to the start of the array
 *      array: array to be modified
 *      length: <= 30
 *      tail: number of elememts to be copied
 */
uint32_t formRow(uchar head, uchar array[], uchar length, uchar tail) {
    uchar temp[32];
    temp[0] = head;
    for (int i = 0 ; i < length + 1; i ++) {
        if (i != length) {
            temp[i+ 1] = array[i];
        }
        else {
            temp[i + 1] = tail;
        }
    }
    return bytesToBits(temp, length + 2);
}
/*
 * adhoc compress
 */
uint32_t compress(uchar array[], uchar length) {
    uint32_t val = 0;
    for (int i = 0; i < length; i ++) {
        if (array[i] == 255) {
            val = val | 0x00000001 << (30 - i);
        }
    }
    return val;
}

uint32_t assignEdges(uint32_t left, uint32_t middle,uchar midLength, uint32_t right) {
    uint32_t val = middle;
    if (returnBitInt(left,31) == 255) {
        val = val | 0x00000001 << 31;
    }
    if (returnBitInt(right,1) == 255) {
        val = val | 0x00000001 << (31 - midLength);
        val = val | 0x00000001;
    }
    return val;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[30];
  uint32_t row[uintArrayWidth];
  uchar length = 0;
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  for( int y = 0; y < IMHT; y++ ) {
      length = 30;
      //reads in a single row
      for (int i = 0; i < uintArrayWidth; i++ ) {
          if (i == ceil(IMWD / 30)) {
              length = IMWD % 30;
          }
          _readinline( line, length);
          row[i] = compress(line,length);

      }
      //assign edges to rows
      for (int i = 0; i < uintArrayWidth; i++ ) {
          length = 30;
          if (i == ceil(IMWD / 30)) {
              length = IMWD % 30;
          }
          row[i] = assignEdges(row[(i-1+uintArrayWidth) % uintArrayWidth], row[i],length, row[ (i + 1) %uintArrayWidth]);
          c_out <: row[i];
      }

  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );

  return;
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_fromButtons, chanend c_toLEDs, chanend c_in, chanend c_out, chanend fromAcc,  chanend c_toWorker[n], unsigned n)
{
  uint32_t linePart[uintArrayWidth][IMHT];
  uint32_t copyPart[uintArrayWidth][IMHT];
  int buttonPressed;  // The button pressed on the xCore-200 Explorer.

  uchar safe = 0; // safe to send to workers

  /*
   * index[j][i] for the workers
   * first column represents row sent
   * second represent column sent
   */
  uchar index[NumberOfWorkers][2];

  //initialise array
  for (int i = 0; i < NumberOfWorkers; i ++) {
      for (int j = 0; j < 2; j ++) {
          index[i][j] = 0;
      }
  }

  uchar i = 0;  //index for the width of input array
  uchar j = 0;  //index for height of input array

  uchar k = 0; //number of rows sent.
  uchar l = 0; //number of columns sent.
  uchar turn = 1; // turn number

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );

  // Start up and wait for SW1 button press on the xCORE-200 eXplorer.
  printf( "Waiting for SW1 button press...\n" );
  int initiated = 0;  // Whether processing has been initiated.

  while (!initiated) {
      c_fromButtons :> buttonPressed;
      if (buttonPressed == SW1) {
          initiated = 1;
      }
  }
  c_toLEDs <: GRN;  // Turn ON the green LED to indicate reading of the image has STARTED.

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  while (turn) {
      if (k == IMHT) { turn = 0; } //ends turn
      if (j == 3) { // starts to work the worker i.
          for (int x = 0; x < 3 ; x++) {
              c_toWorker[0] <: linePart[0][j - 1 - x + IMHT % IMHT];
          }
          safe = 0;
      }
      select {
        //case when receiving from the (main distributor).
        case c_in :> linePart[i][j]:

            i = i + 1 % uintArrayWidth;
            if (i == 0) { j++; } //increment height when i goes over the "edge";
            break;
        //when safe for worker to send back data.
        //case when receiving from the work.
        case safe => c_toWorker[0] :> uint32_t output:
            copyPart[l][(k + 1) % IMHT] = output;
            for (int x = 0; x < 3 ; x++) {
                c_toWorker[0] <: linePart[l][(k - x + 3 + IMHT) % IMHT];
            }
            l = l + 1 % uintArrayWidth;
            if (l == 0) { k ++; }
            break;
      }

      //Varies if conditions for unsafe working of worker.
      if (k + 3 <= j && j < IMHT) { safe = 1; }
      else if (j == IMHT) {
          safe = 1; }
      else { safe = 0; }
  }

  c_toLEDs <: OFF;  // Turn OFF the green LED to indicate reading of the image has FINISHED.

  printf( "\nOne processing round completed...\n" );
  for (int i = 0; i < IMHT; i++) {
      for (int j = 0; j < uintArrayWidth ; j++) {
          printBinary(copyPart[j][i], 16);
      }
  }
}

uchar deadOrAlive(uchar state, uchar count) {
    if (state == 255) {
        if (count < 2 || count > 3) {
            return 0;
        }
    }
    // If dead
    else if (count == 3) {
        return 255;    // Now alive.
    }
    return state;
}


uchar isTwoFiveFive(uchar input) {
    if (input == 255) {
        return 1;
    } else {
        return 0;
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Worker that processes part of the image.
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker(chanend c_fromDist) {
    uint32_t lines[3];
    uchar results[30];
    uchar count = 0;
    uchar state = 0;
    while (1) {
        for (int i = 0; i < 3; i++) {

            c_fromDist :> lines[i];
        }
        for (int j = 1 ; j < 31; j++) { // goes through each bit in the input
            count = 0;
            state = 0;
            for (int i = 0; i < 3; i++) { // goes through each row
                count = count + isTwoFiveFive(returnBitInt(lines[i], j + 1));
                count = count + isTwoFiveFive(returnBitInt(lines[i], j - 1));
                if (i != 1) {
                    count = count + isTwoFiveFive(returnBitInt(lines[i], j));
                }
                else {
                    state = returnBitInt(lines[i], j);
                }
            }
            results[j - 1] = deadOrAlive(state, count);
        }
        uint32_t output = bytesToBits(results, 30);
        c_fromDist <: output;
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
    printf( "DataOutStream: Line written...\n" );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
    i2c_regop_res_t result;
    char status_data = 0;
    int vertical = 0;

    // Configure FXOS8700EQ.
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
    if (result != I2C_REGOP_SUCCESS) {
        printf("I2C write reg failed\n");
    }

    // Enable FXOS8700EQ.
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
    if (result != I2C_REGOP_SUCCESS) {
        printf("I2C write reg failed\n");
    }

    // Probe the orientation x-axis forever and inform the distributor of orientation changes.
    while (1) {
        // Check until new orientation data is available.
        do {
            status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
        } while (!status_data & 0x08);

        // Get new x-axis tilt value.
        int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

        // If previously horizontal
        if (!vertical) {
            // If now vertical, tell the distributor.
            if (x >= 125) {
                vertical = 1;
                toDist <: 1;
            }
        }
        // If previously vertical
        else {
            // If now horizontal, tell the distributor.
            if (x == 0) {
                vertical = 0;
                toDist <: 1;
            }
        }
    }

}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation


char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here
chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
chan c_workers[NumberOfWorkers];     // Worker channels (one for each worker).
chan c_buttonsToDist, c_DistToLEDs;  // Button and LED channels.

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0],c_control);        //client thread reading orientation data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_buttonsToDist, c_DistToLEDs, c_inIO, c_outIO, c_control, c_workers, NumberOfWorkers);//thread to coordinate work on image
    worker(c_workers[0]);                  // thread to do work on an image.

    buttonListener(buttons, c_buttonsToDist);  // Thread to listen for button presses.
    showLEDs(leds, c_DistToLEDs);              // Thread to process LED change requests.
  }

  return 0;
}
