// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <math.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 64                  //image height
#define  IMWD 64                  //image width
//the variables below must change when image size changes
#define SPLITWIDTH 2
#define UINTARRAYWIDTH 3            //ceil(IMWD / 30)

#define NUMBEROFWORKERS 3         //number of workers
#define NUMBEROFSUBDIST 2   //number of subdistributors.

// Port to access xCORE-200 buttons.
on tile[0]: in port buttons = XS1_PORT_4E;
// Buttons signals.
#define SW2 13     // SW2 button signal.
#define SW1 14     // SW1 button signal.

// Port to access xCore-200 LEDs.
on tile[0]: out port leds = XS1_PORT_4F;
// LED signals.
#define OFF  0     // Signal to turn the LED off.
#define GRNS 1     // Signal to turn the separate green LED on.
#define BLU  2     // Signal to turn the blue LED on.
#define GRN  4     // Signal to turn the green LED on.
#define RED  8     // Signal to turn the red LED on.

// Interface ports to orientation
on tile[0]: port p_scl = XS1_PORT_1E;
on tile[0]: port p_sda = XS1_PORT_1F;

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

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here


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
void buttonListener(in port b, chanend c_toDataIn, chanend c_toDist) {
    int r;  // Received button signal.
    while (1) {
        b when pinseq(15)  :> r;     // Check that no button is pressed.
        b when pinsneq(15) :> r;     // Check if some buttons are pressed.
        if (r == SW1) {  // If either button is pressed
            c_toDataIn <: r;           // send button pattern to distributor.
        }
        if (r == SW2) {
            c_toDist <: r;
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

/*
 * assignLeftEdge assumes that left is already in the correct form).
 */
uint32_t assignLeftEdge(uint32_t left, uchar leftLength, uint32_t middle) {
    uint32_t val = middle;
    if (returnBitInt(left,leftLength) == 255) {
        val = val | 0x00000001 << 31;
    }
    return val;
}
/*
 * right does not have to be of correct form.
 */
uint32_t assignRightEdge(uint middle, uchar midLength, uint32_t right) {
    uint32_t val = middle;
    if (returnBitInt(right,1) == 255) {
        val = val | 0x00000001 << (30 - midLength);
        val = val | 0x00000001;
    }
    return val;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out, chanend c_fromButtons)
{
  int res;
  uchar line[30];
  uint32_t row[UINTARRAYWIDTH];
  uchar length = 0;
  int buttonPressed;  // The button pressed on the xCore-200 Explorer.
  // Start up and wait for SW1 button press on the xCORE-200 eXplorer.
  printf( "Waiting for SW1 button press...\n" );
  int initiated = 0;  // Whether processing has been initiated.

  while (!initiated) {
      c_fromButtons :> buttonPressed;
      if (buttonPressed == SW1) {
          initiated = 1;
      }
  }
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
      for (int i = 0; i < UINTARRAYWIDTH; i++ ) {
          if (i == ceil(IMWD / 30)) {
              length = IMWD % 30;
          }
          _readinline( line, length);
          row[i] = compress(line,length);
      }
      //assign edges to rows
      for (int i = 0; i < UINTARRAYWIDTH; i++ ) {
          length = 30;
          if (i + 1 == UINTARRAYWIDTH) {
              length = IMWD % 30;
          }
          row[i] = assignRightEdge(row[i], length, row[ (i + 1) % UINTARRAYWIDTH]);

      }
      for (int i = 0; i < UINTARRAYWIDTH; i++ ) {
          length = 30;
          if ((i - 1 + UINTARRAYWIDTH) % UINTARRAYWIDTH == UINTARRAYWIDTH - 1) {
              length = IMWD % 30;
          }
          row[i] = assignLeftEdge(row[(i-1+UINTARRAYWIDTH) % UINTARRAYWIDTH], length, row[i]);
          c_out <: row[i];
      }
  }


  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );

  return;
}

void mainDistributor(chanend c_fromButtons, chanend c_toLEDs, chanend fromAcc, chanend c_in, chanend c_out, chanend c_subDist[n], unsigned n) {
    //various variables to control the state of the same.
    uchar pause = 0; //this needs changing
    uchar turn = 0;
    uchar aliveCells = 0;
    uchar rightDone = 0;
    uchar leftDone = 0;
    uchar end = 0;
    uchar length = 0;
    uint32_t val;
    uint32_t edges[4];

    int buttonPressed;  // The button pressed on the xCore-200 Explorer.
    //sending distributors information about the array size to be used.
    c_subDist[0] <: (uint32_t) SPLITWIDTH;
    c_subDist[1] <: (uint32_t) UINTARRAYWIDTH - SPLITWIDTH;
    //Distributing image from c_in to sub distributors.
    for( int i = 0; i < IMHT; i++ ) {
        for (int j = 0; j < UINTARRAYWIDTH; j++) {
            c_in :> val;
            if (j < SPLITWIDTH) {
                c_subDist[0] <: val;
            } else {
                c_subDist[1] <: val;
            }
        }
    }
    length = IMWD % 30;
    while (1) {
        select {
            case c_fromButtons :> buttonPressed: //export state
                if (buttonPressed == SW2) { //Export state.
                    end = 1;
                }
                else if (buttonPressed == SW1) {
                    pause = pause + 1 % 2;
                }
                //recieve data from distributors
                break;
            case fromAcc :> pause:
                //Send signal to distributor.
                break;
            case c_subDist[int i] :> val:
                aliveCells = aliveCells + val;

                //wait for other subDist
                c_subDist[(i + 1) % 2] :> val;
                turn++ ;
                aliveCells = aliveCells + val;

                if (pause == 0) { c_subDist[1] <: 0; c_subDist[0] <: 0; }// change this from to 1 (for debug)
                else if (pause == 1) {  c_subDist[0] <: 1; c_subDist[1] <: 1; }


                aliveCells = 0; //reset alive cells at the end of each round.
                for (int i = 0; i < 4; i++) { //initialise edges to 0.
                    edges[i] = 0;
                }

                if (pause == 0) { //assign edges
                    for (int i = 0; i < IMHT; i ++ ){
                        for (int j = 0; j < 4; j++ ) {// receiving edges
                            select {
                               case c_subDist[int l] :> uint32_t edge:
                                   uchar k = 0;
                                   uchar m = 2;
                                   if (l == 0) {
                                       edges[k] = edge;
                                       k ++;
                                   }
                                   else {
                                       edges[m] = edge;
                                       m ++;
                                   }
                                   break;
                             }
                         }
                         edges[3] = assignRightEdge(edges[3],length, edges[0]);
                         edges[0] = assignLeftEdge(edges[3], 30,  edges[0]);
                         edges[1] = assignRightEdge(edges[1], 30, edges[2]);
                         edges[2] = assignLeftEdge(edges[1], 30, edges[2]);
                         for (int j = 0; j < 2; j ++) {
                             c_subDist[0] <: edges[j];
                             c_subDist[0] <: edges[j+2];
                         }
                     }
                     rightDone = 0;
                     leftDone = 0;
                     printf("done\n");
                }

                if (pause == 1) {//recieve picture for debug purposes.
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0 ; j < UINTARRAYWIDTH; j ++) {
                            length = 30;
                            if (j == UINTARRAYWIDTH - 1) { length = IMWD % 30; }
                            if (j < SPLITWIDTH) {
                                c_subDist[0] :> val;
                                printBinary(val,length);
                            } else {
                                c_subDist[1] :> val;
                                printBinary(val,length);
                            }
                        }
                        printf("\n");
                    }
                }
                break;

        }
    }
    c_toLEDs <: OFF;  // Turn OFF the green LED to indicate reading of the image has FINISHED.
    c_toLEDs <: GRN;  // Turn ON the green LED to indicate reading of the image has STARTED.
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void subDistributor(chanend c_in, chanend c_toWorker[n], unsigned n)
{
  uint32_t linePart[SPLITWIDTH][IMHT]; //stores processing image
  uint32_t copyPart[SPLITWIDTH][IMHT]; //stores results.
  uchar readIn = 1; //boolean for reading in files.
  uchar safe = 0; // safe to send to workers

  uchar distColsReceived = 0;   //number of columns received from the distributor.
  uchar distRowsReceived = 0;  //numbers of rows received from the distributor

  uint32_t actualWidth = 0; // actual width of the array used.
  uint32_t val = 0;

  /*
   * index[j][i] for the workers
   * first column represents cols sent
   * second represent rows sent
   */
  uchar index[NUMBEROFWORKERS][2];

  uchar pause = 0; // boolean for pause state
  uchar nextTurn = 0; //boolean for next Turn

  uchar workerColsReceived = 0; //number of columns received from workers
  uchar workerRowsReceived = 0; //number of rows received from workers

  uchar workerColsSent = 0; //number of columns sent to the worker. l
  uchar workerRowsSent = 0; //number of rows sent to the worker. k

  uchar workersStarted = 0; //number of workers starting to work

  //initialise array
  for (int i = 0; i < NUMBEROFWORKERS; i ++) {
      for (int j = 0; j < 2; j ++) {
          index[i][j] = 0;
      }
  }

  //Getting actual width from main dsitributor
  c_in :> actualWidth;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, actualWidth );

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  while (1) {
      if (distRowsReceived == IMHT) { readIn = 0; } //finished readIn!
      if (workerRowsSent == IMHT && workerRowsReceived == IMHT) { nextTurn = 1; } //next turn!!
      // starts to work the workers.
      if (safe && workersStarted < NUMBEROFWORKERS) {
          for (int x = 0; x < 3 ; x++) {
              c_toWorker[workersStarted] <: linePart[workerColsSent % actualWidth][(workerRowsSent - 1 + x + IMHT) % IMHT];
          }
          index[workersStarted][0] = workerColsSent % actualWidth;
          index[workersStarted][1] = workerRowsSent % IMHT;
          workerColsSent ++;
          if (workerColsSent % actualWidth == 0) { workerRowsSent ++; }
          workersStarted ++;
      }
      // various conditions for "safety"
      //Various if conditions for unsafe working of worker.

      if (distRowsReceived == IMHT) { safe = 1;  }
      //else if (workerRowsSent + 3 <= distRowsReceived && distRowsReceived < IMHT) { safe = 1; }
      else { safe = 0; }
      select {
        //case when receiving from the (main distributor).
        case c_in :> val:
            if (readIn) {
                linePart[distColsReceived % actualWidth][distRowsReceived] = val;
                distColsReceived ++;
                if (distColsReceived % actualWidth == 0) { distRowsReceived ++; } //increment height when i goes over the "edge";
            }
            else if (nextTurn == 0) {
                if (val == 0) {
                    pause = 1;
                }
                else if (val == 1) {
                    pause = 0;
                }
            }
            break;
        //when safe for worker to send back data.
        //case when receiving from the work.
        case (safe) => c_toWorker[int i] :> copyPart[(int) index[i][0]][(int) index[i][1]]:
            workerColsReceived++;
            if (workerColsReceived % actualWidth == 0) { workerRowsReceived ++; }
            if (workerRowsSent < IMHT) {
                for (int x = 0; x < 3 ; x++) {
                    c_toWorker[i] <: linePart[workerColsSent % actualWidth][(workerRowsSent + 1 - x + IMHT) % IMHT];
                }
                index[i][0] = workerColsSent % actualWidth;
                index[i][1] = workerRowsSent % IMHT;
                workerColsSent ++;
                if (workerColsSent % actualWidth == 0) { workerRowsSent ++; }
            }
            break;
        default:
            if (nextTurn){
                //letting distributor know (this) is ready
                c_in <: 1;
                c_in :> val;
                if (val == 1) { pause = 1; }
                else { pause = 0; }
                //send edges cases when not paused.

                if (pause == 0) {
                    printf( "\nOne processing round completed...\n" );
                    //logic for sending edges
                    for (int i = 0; i < IMHT; i++){
                        for (int j = 0; j < actualWidth; j++) {
                            if (j  < actualWidth - 1) {
                                linePart[j][i] = assignRightEdge(copyPart[j][i],30,copyPart[j + 1][i]);
                            }
                            if (j > 0) {
                                linePart[j][i] = assignLeftEdge(copyPart[j - 1][i], 30, copyPart[j][i]);
                            }
                        }
                        c_in <: linePart[0][i];
                        c_in <: linePart[actualWidth - 1][i];
                        c_in :> linePart[0][i];
                        c_in :> linePart[actualWidth - 1][i];
                    }
                }

                //send image to main distributor.
                if (pause) {
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0; j < actualWidth; j ++) {
                            c_in <: copyPart[j][i];
                        }
                    }
                }
                // reset variables for next turn.
                nextTurn = 0;
                workerColsReceived = 0;
                workerRowsReceived = 0;
                workerColsSent = 0;
                workerRowsSent = 0;
                workersStarted = 0;
            }

            break;
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
        for (int j = 1; j < 31; j++) { // goes through each bit in the input
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
        uint32_t output = 0;
        output = compress(results, 30);
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

chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
chan c_workers[NUMBEROFWORKERS];     // Worker channels (one for each worker).
chan c_otherWorkers[NUMBEROFWORKERS];
chan c_buttonsToDist, c_DistToLEDs, c_buttonsToData;  // Button and LED channels.
chan c_subDist[NUMBEROFSUBDIST];

par {
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[1]: orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[1]: DataInStream(infname, c_inIO, c_buttonsToData);          //thread to read in a PGM image
    on tile[1]: DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    on tile[1]: mainDistributor(c_buttonsToDist, c_DistToLEDs , c_control, c_inIO, c_outIO, c_subDist, NUMBEROFSUBDIST);
    on tile[1]: subDistributor(c_subDist[0], c_workers, NUMBEROFWORKERS);//thread to coordinate work on image
    on tile[0]: subDistributor(c_subDist[1], c_otherWorkers, NUMBEROFWORKERS);//thread to coordinate work on image
    par (int i = 0; i < NUMBEROFWORKERS; i++){ //making workers
        on tile[1]: worker(c_workers[i]);                  // thread to do work on an image.
        on tile[0]: worker(c_otherWorkers[i]);
    }

    on tile[0]: buttonListener(buttons,c_buttonsToData, c_buttonsToDist);  // Thread to listen for button presses.
    on tile[0]: showLEDs(leds, c_DistToLEDs);              // Thread to process LED change requests.
  }

  return 0;
}
