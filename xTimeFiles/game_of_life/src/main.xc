// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <math.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 128                  //image height
#define  IMWD 128                  //image width
//the variables below must change when image size changes
#define SPLITWIDTH 3                //ceil(UINTARRAYWIDTH /2)
#define UINTARRAYWIDTH 5            //ceil(IMWD / 30)
#define RUNUNTIL 1                  //for debug
//Number of ...
#define NUMBEROFWORKERS 3         //Workers
#define NUMBEROFSUBDIST 2   //Sub-Distributors.

//Signals sent from master to sub distributors. State of the farm.
#define CONTINUE 0
#define PAUSE    1
#define STOP     2

// Buttons signals.
#define SW2 13     // SW2 button signal.
#define SW1 14     // SW1 button signal.

// LED signals.
#define OFF  0     // Signal to turn the LED off.
#define GRNS 1     // Signal to turn the separate green LED on.
#define BLU  2     // Signal to turn the blue LED on.
#define GRN  4     // Signal to turn the green LED on.
#define RED  8     // Signal to turn the red LED on.

// Interface ports to orientation
on tile[0]: port p_scl = XS1_PORT_1E;
on tile[0]: port p_sda = XS1_PORT_1F;

// Port to access xCore-200 LEDs.
on tile[0]: out port leds = XS1_PORT_4F;

// Port to access xCORE-200 buttons.
on tile[0]: in port buttons = XS1_PORT_4E;

//register addresses for orientation
#define FXOS8700EQ_I2C_ADDR 0x1E
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
// Provides the value of the current tile's timer in seconds.
//
/////////////////////////////////////////////////////////////////////////////////////////
double getCurrentTime() {
    double time;
    timer t;
    t :> time;
    time /= 100000000;  // Convert to seconds.
    return time;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Prints a status report to the terminal; including rounds processed, number of live
// cells in last round, and the time elapsed since the original image was read in.
//
/////////////////////////////////////////////////////////////////////////////////////////
void printStatusReport(double start, double current, int rounds, int liveCells, int final) {
    double time = current - start;  // Total time elapsed.

    printf("\n----------------------------------\n");
    if (final) {
        printf("FINAL STATUS REPORT:\n");
    }
    else {
        printf("PAUSED STATE STATUS REPORT:\n");
    }
    printf("Rounds Processed: %d\n"
           "Live Cells: %d / %d\n"
           "Time Elapsed: %.4lf seconds\n"
           "Number of workers: %d\n"
           "----------------------------------\n\n",
           rounds, liveCells, IMHT*IMWD, time, NUMBEROFWORKERS);
}


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
uchar getBit(uint32_t queriedInt, uchar index) {
    if ( (queriedInt & 0x00000001 << (31 - index)) == 0 ) {
        return 0;
    }
    else {
        return 255;
    }
}

/*
 * Count alive cells in a uint32_t
 */
uint32_t numberOfAliveCells(uint32_t cells, uchar length) {
    int count = 0;
    for (int i = 1; i < length + 1; i ++) {
        if (getBit(cells, i) == 255) { count++; }
    }
    return count;
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
 * assignLeftEdge: assigns the left "edge value" to the "middle" row.
 */
uint32_t assignLeftEdge(uint32_t left, uchar leftLength, uint32_t middle) {
    uint32_t val = middle;
    if (getBit(left,leftLength) == 255) {
        val = val | 0x00000001 << 31;
    }
    else {
        val = val & 0x7FFFFFFF;
    }
    return val;
}
/*
 * assignRightEdge: assigns the right "edge value" to the "middle row.
 */
uint32_t assignRightEdge(uint middle, uchar midLength, uint32_t right) {
    uint32_t val = middle;
    printf("Bitshifttest\n%d\n%d\n\n",0x00000001,0x00000001);
    if (getBit(right,1) == 255) {
        val = val | 0x00000001 << (30 - midLength);
        val = val | 0x00000001;
    } else {
        val = val & 0xFFFFFFFE << (30 - midLength);
        val = val & 0xFFFFFFFE; // 1 1 1 ... 1 1 0
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

  while (!initiated) { //wait until SW1 button has been pressed.
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

      //reads in a single row from file.
      for (int i = 0; i < UINTARRAYWIDTH; i++ ) {
          length = 30;
          if (i == ceil(IMWD / 30)) {
              length = IMWD % 30;
          }
          _readinline( line, length);
          row[i] = compress(line,length); // compresses into bits.
      }

      //assign edges values to each row.
      for (int i = 0; i < UINTARRAYWIDTH; i++ ) {
          //assign right edge
          length = 30;
          if (i + 1 == UINTARRAYWIDTH) {
              length = IMWD % 30;
          }
          row[i] = assignRightEdge(row[i], length, row[ (i + 1) % UINTARRAYWIDTH]);
          length = 30;

          //assign left edge
          if ((i - 1 + UINTARRAYWIDTH) % UINTARRAYWIDTH == UINTARRAYWIDTH - 1) {
              length = IMWD % 30;
          }
          row[i] = assignLeftEdge(row[(i- 1 + UINTARRAYWIDTH) % UINTARRAYWIDTH], length, row[i]);
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
    double start;           // Start time for processing.
    double current;         //time after processing a round.
    uchar state = 0;        //Signal to the sub distributors the state of the farm.
    int turn = 0;           //turn number
    int aliveCells = 0;     //number of live cells at turn
    uchar length = 0;
    uint32_t val;           //read in value.
    uint32_t edges[4];      //store edges.

    int buttonPressed;  // The button pressed on the xCore-200 Explorer.

    //sending distributors information about the array size to be used.
    c_subDist[0] <: (uint32_t) SPLITWIDTH;
    c_subDist[1] <: (uint32_t) UINTARRAYWIDTH - SPLITWIDTH;

    //Distributing image from dataInstream to sub distributors.
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

    while (1) {
        select {
            case c_fromButtons :> buttonPressed: //export state
                if (buttonPressed == SW2) { //Export state.
                    printf("STOP\n");
                    state = STOP;
                }
                //recieve data from distributors
                break;

            case fromAcc :> val:
                if (val == 1) { state = 1; }
                else if ( val == 0 ) { state = 0; }
                break;

            case c_subDist[int i] :> val:
                //reseting variables.
                aliveCells = 0;
                for (int i = 0; i < 4; i++) { edges[i] = 0; }

                aliveCells = aliveCells + val;
                c_subDist[(i + 1) % 2] :> val; //wait for other subDist
                printf( "\nRound %d completed...\n", turn);
                turn++ ; //increment turn.
                aliveCells = aliveCells + val;

                if (turn == RUNUNTIL ) { state = 2; }

                //sending the pause state to distributor.
                if (state == CONTINUE)   { c_subDist[1] <: 0; c_subDist[0] <: 0; }
                else if (state == PAUSE) { c_subDist[0] <: 1; c_subDist[1] <: 1; }
                else if (state == STOP)  { c_subDist[0] <: 2; c_subDist[1] <: 2; }

                //if not paused, receive images edges from sub distributor to be assigned edges.
                if (state == 0) {
                    for (int i = 0; i < IMHT; i ++ ){
                        //receiving edges
                        c_subDist[0] :> edges[0];
                        c_subDist[0] :> edges[1];
                        c_subDist[1] :> edges[2];
                        c_subDist[1] :> edges[3];
                        //assigning edges
                        edges[3] = assignRightEdge(edges[3],IMHT % 30, edges[0]);
                        edges[0] = assignLeftEdge(edges[3], IMHT % 30,  edges[0]);
                        edges[1] = assignRightEdge(edges[1], 30, edges[2]);
                        edges[2] = assignLeftEdge(edges[1], 30, edges[2]);
                        if (UINTARRAYWIDTH - SPLITWIDTH == 1) {
                            edges[3] = assignLeftEdge(edges[1], 30, edges[3]);
                            edges[2] = assignRightEdge(edges[2],IMHT % 30, edges[0]);
                        }

                        for (int j = 0; j < 2; j ++) {
                            c_subDist[0] <: edges[j];
                            c_subDist[1] <: edges[j+2];
                        }
                     }
                }
                else {
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0 ; j < UINTARRAYWIDTH; j ++) {
                            length = 30;
                            if (j == UINTARRAYWIDTH - 1) { length = IMWD % 30; }
                            if (state == PAUSE) { // if paused, then ...
                                if (j < SPLITWIDTH) {
                                    c_subDist[0] :> val;
                                    printBinary(val,length);
                                } else {
                                    c_subDist[1] :> val;
                                    printBinary(val,length);
                                }
                            }
                            else if (state == STOP) { // if stop then send data to data out.
                                if (j < SPLITWIDTH) { c_subDist[0] :> val; }
                                else { c_subDist[1] :> val; }

                                //splitting uint32_t into its constituent bits.
                                for (int l = 1 ; l < length + 1 ; l ++) {
                                    c_out <: getBit(val, l);
                                }
                            }
                        }
                        if (state == PAUSE) {
                            printf("\n");
                        }
                    }

                    c_subDist[0] :> val;
                    aliveCells = val;
                    c_subDist[1] :> val;
                    aliveCells = aliveCells + val;
                    printStatusReport(start, current, turn, aliveCells, state - 1);
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
  uint32_t aliveCells = 0;
  uchar length = 0;

  /*
   * index[j][i] for the workers
   * first column represents cols sent
   * second represent rows sent
   */
  uint32_t index[NUMBEROFWORKERS][2];

  uchar state = 0; // boolean for pause state
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
  while (state != STOP) {
      if (distRowsReceived == IMHT) { readIn = 0; } //finished readIn!
      if (workerRowsSent == IMHT && workerRowsReceived == IMHT) { nextTurn = 1; } //next turn!!

      // starts to work the workers.
      if (safe && workersStarted < NUMBEROFWORKERS) {
          for (int x = 0; x < 3 ; x++) {
              c_toWorker[workersStarted] <: linePart[workerColsSent % actualWidth][(workerRowsSent + x) % IMHT];
          }
          index[workersStarted][0] = workerColsSent % actualWidth;
          index[workersStarted][1] = (workerRowsSent + 1) % IMHT;
          workerColsSent ++;
          if (workerColsSent % actualWidth == 0) { workerRowsSent ++; }
          workersStarted ++;
      }

      // various conditions for "safety"
      //Various if conditions for unsafe working of worker.
      if (readIn) {
          if (workerRowsSent + 2 < distRowsReceived ) {
              safe = 1;
          }
          else { safe = 0; }
      }
      else { safe = 1; }

      select {
        //case when receiving from the (main distributor).
        case c_in :> val:
            if (readIn) {
                linePart[distColsReceived % actualWidth][distRowsReceived] = val;
                distColsReceived ++;
                if (distColsReceived % actualWidth == 0) { distRowsReceived ++; } //increment height when i goes over the "edge";
            }
            break;

        //when safe for worker to send back data.
        //case when receiving from the work.
        case (safe) => c_toWorker[int i] :> copyPart[index[i][0]][index[i][1]]:
                workerColsReceived++;
                if (workerColsReceived % actualWidth == 0) { workerRowsReceived ++; }
                if (workerRowsSent < IMHT) {
                    for (int x = 0; x < 3 ; x++) {
                        c_toWorker[i] <: linePart[workerColsSent % actualWidth][(workerRowsSent + x + IMHT) % IMHT];
                    }
                    index[i][0] = workerColsSent % actualWidth;
                    index[i][1] = (workerRowsSent  + 1) % IMHT;
                    workerColsSent ++;
                    if (workerColsSent % actualWidth == 0) { workerRowsSent ++; }
                }
                break;


        default:
            if (nextTurn){
                //letting distributor know (this) is ready
                c_in <: 1;
                c_in :> val;
                if (val == 0)      { state = CONTINUE; }
                else if (val == 1) { state = PAUSE; }
                else if (val == 2) { state = STOP; }

                //send edges cases when not paused.
                if (state == CONTINUE) {
                    //logic for sending edges
                    for (int i = 0; i < IMHT; i++){
                        for (int j = 0; j < actualWidth; j++) {
                            linePart[j][i] = copyPart[j][i];
                            uchar length = 30;
                            if (actualWidth < SPLITWIDTH && j == actualWidth - 1) {
                                length = IMHT % 30;
                            }
                            if (j  < actualWidth - 1) {
                                linePart[j][i] = assignRightEdge(copyPart[j][i], length, copyPart[j + 1][i]);
                            }
                            if (j > 0) {
                                linePart[j][i] = assignLeftEdge(copyPart[j - 1][i], length, copyPart[j][i]);
                            }
                        }

                        //when actualWidth == 1 we have a problem
                        c_in <: linePart[0][i];
                        c_in <: linePart[actualWidth - 1][i];
                        c_in :> linePart[0][i];
                        c_in :> linePart[actualWidth - 1][i];
                    }
                }
                else {
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0; j < actualWidth; j ++) {
                            length = 30;
                            if (j == actualWidth -1 ) {
                                length = IMWD % 30;
                            }
                            if (state == PAUSE) {
                                c_in <: copyPart[j][i]; // for debug sending image to be printed.
                            }
                            else if (state == STOP){ // if end send image to be printed.
                                c_in <: copyPart[j][i];
                            }
                            aliveCells = aliveCells + numberOfAliveCells(copyPart[j][i], length);
                        }
                    }
                }

                //send image to main distributor.
                if (state == PAUSE) {
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0; j < actualWidth; j ++) {
                            c_in <: copyPart[j][i];
                            length = 30;
                            if (j == actualWidth -1 ) {
                                length = IMWD % 30;
                            }
                            aliveCells = aliveCells + numberOfAliveCells(copyPart[j][i], length);
                        }
                    }
                    c_in <: aliveCells;
                    c_in :> val;
                    state = val;
                    //c_in :>
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

/*
 * Return if cell is dead or alive depending on
 * the current state and count.
 */
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
                count = count + isTwoFiveFive(getBit(lines[i], j + 1));
                count = count + isTwoFiveFive(getBit(lines[i], j - 1));
                if (i != 1) {
                    count = count + isTwoFiveFive(getBit(lines[i], j));
                }
                else {
                    state = getBit(lines[i], j);
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
  uchar bit[1];

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
      c_in :> bit[0];
      _writeoutline(bit, 1);
    }
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
                toDist <: 0;
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
