// COMS20001 - Cellular Automaton Farm - Geometric Farming (Hybrid) using bit compression.
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <math.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

/*
 * IMHT           16    32   64    128   256   512   1200    2048   1280    1024
 *
 * SPLITWIDTH       1    1    2      3    5    9       20      35     22    18
 * UINTARRAYWIDTH   1    2    3      5    9    18      40      69     43    35
 */
#define  IMHT 256                         // Image height
#define  IMWD 256                         // Image width

// The variables below must change when image size changes
#define SPLITWIDTH      5                 // Ceil(UINTARRAYWIDTH /2)
#define UINTARRAYWIDTH  9                 // Ceil(IMWD / 30)
#define RUNUNTIL       1000               // For debug

// Number of ...
#define NUMBEROFWORKERS 3                 // Number of workers for each sub distributor.
#define NUMBEROFSUBDIST 2                 // Sub-Distributors.

// Signals sent from master to sub distributors. State of the farm.
#define CONTINUE 0
#define PAUSE    1
#define STOP     2

// Buttons signals.
#define SW2 13                          // SW2 button signal.
#define SW1 14                          // SW1 button signal.

// LED signals.
#define OFF  0                          // Signal to turn the LED off.
#define GRNS 1                          // Signal to turn the separate green LED on.
#define BLU  2                          // Signal to turn the blue LED on.
#define GRN  4                          // Signal to turn the green LED on.
#define RED  8                          // Signal to turn the red LED on.

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

typedef unsigned char uchar;                    //using uchar as shorthand

char infname[] = "256x256.pgm";                //put your input image path here
char outfname[] = "256x256(1000-2other).pgm";  //put your output image path here

/////////////////////////////////////////////////////////////////////////////////////////
//
// Provides the value of the current tile's timer in seconds.
//
/////////////////////////////////////////////////////////////////////////////////////////
double getCurrentTime() {
    double time;
    timer t;
    t :> time;
    time /= 100000000;                 // Convert to seconds.
    return time;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Prints a status report to the terminal; including rounds processed, number of live
// cells in last round, and the time elapsed since the original image was read in.
//
/////////////////////////////////////////////////////////////////////////////////////////
void printStatusReport(double totalTime, int rounds, int liveCells, int final) {

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
           "Average Time/Round: %.4lf seconds\n"
           "Number of workers: %d\n"
           "----------------------------------\n\n",
           rounds, liveCells, IMHT*IMWD, totalTime, totalTime / rounds, NUMBEROFWORKERS);
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// READ BUTTONS and send button pattern to distributor.
//
/////////////////////////////////////////////////////////////////////////////////////////
void buttonListener(in port b, chanend c_toDataIn, chanend c_toDist) {
    int r;                                     // Received button signal.
    uchar sw1Pressed = 0;                          // Has button been pressed before?
    while (1) {
        b when pinseq(15)  :> r;                 // Check that no button is pressed.
        b when pinsneq(15) :> r;                 // Check if some buttons are pressed.
        if (r == SW1 && sw1Pressed == 0) {       // If SW1 pressed, and not pressed before.
            c_toDist <: r;                       // send button pattern to dataInStream.
            sw1Pressed = 1;
        }
        if (r == SW2 && sw1Pressed) {
            c_toDist <: r;                    //// send button pattern to distributor.
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given an int32_t and an index, find the binary representation at the index.
// Return 255 if 1, 0 otherwise.
//
/////////////////////////////////////////////////////////////////////////////////////////
uchar getBit(uint32_t queriedInt, uchar index) {
    if ( (queriedInt & 0x00000001 << (31 - index)) == 0 ) { return 0; }
    else { return 255; }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given an int32_t and an index,
// Return the numbers of 1s in the binary representation.
//
/////////////////////////////////////////////////////////////////////////////////////////
uint32_t numberOfAliveCells(uint32_t cells, uchar length) {
    int count = 0;
    for (int i = 1; i < length + 1; i ++) {
        if (getBit(cells, i) == 255) { count++; }
    }
    return count;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given an int32_t and an index,
// Return the numbers of 1s in the binary representation.
//
/////////////////////////////////////////////////////////////////////////////////////////
uint32_t compress(uchar array[], uchar length) {
    uint32_t val = 0;
    for (int i = 0; i < length; i ++) {
        if (array[i] == 255) {
            val = val | 0x00000001 << (30 - i);
        }
    }
    return val;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given,
// uint32_t left:  the row representation left of the "middle row"
// uint32_t right: the "middle" row to be assigned the edge cases.
// Return the numbers of 1s in the binary representation.
//
/////////////////////////////////////////////////////////////////////////////////////////
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

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given,
// (uint32_t) middle: the row representation left of the "middle" row.
// (uint32_t) right:  the "middle" row to be assigned the edge cases.
// Return the numbers of 1s in the binary representation.
//
/////////////////////////////////////////////////////////////////////////////////////////
uint32_t assignRightEdge(uint middle, uchar midLength, uint32_t right) {
    uint32_t val = middle;
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
void DataInStream(char infname[],  chanend c_out, chanend c_fromButtons)
{
  int res;
  uchar line[30];
  uint32_t row[UINTARRAYWIDTH];
  uchar length = 0;

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

/////////////////////////////////////////////////////////////////////////////////////////
//
// Main Distributor is working
// cells in last round, and the time elapsed since the original image was read in.
//
/////////////////////////////////////////////////////////////////////////////////////////
void mainDistributor(chanend c_fromButtons, chanend fromAcc,  chanend c_in, chanend c_out,  chanend c_subDist[n], unsigned n) {
    //Variables for timings.
    double start = 0;           // Start time for processing.
    double current = 0;         // Time after processing a single round.
    double totalTime = 0;       // Total time spent processing.
    
    // Variables to for "state".
    uchar state = 0;            // State of the farm.
    int round = 1;              // The number of round ran.
    int previousRound = 0;      // Previous round number.
    int aliveCells = 0;         // Number of live cells at turn
    
    //Variables for processing image.
    uchar length = 0;           // Length of actual image.
    uint32_t val;               // Input value.
    uint32_t edges[4];          // Store edges from sub distributor

    int buttonPressed;          // The button pressed on the xCore-200 Explorer.

    // Sending sub distributors information about the array size to be used.
    c_subDist[0] <: (uint32_t) SPLITWIDTH;
    c_subDist[1] <: (uint32_t) UINTARRAYWIDTH - SPLITWIDTH;

    // Start up and wait for SW1 button press on the xCORE-200 eXplorer.
    printf( "Waiting for SW1 button press...\n" );
    int initiated = 0;                              // Whether processing has been initiated.

    while (!initiated) {                            // Wait until SW1 button has been pressed.
        c_fromButtons :> buttonPressed;
        if (buttonPressed == SW1) {
            initiated = 1;
            leds <: GRN;
        }
    }

    // Distributing image from dataInstream to sub distributors.
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

    // Records the start time.
    start = getCurrentTime();

    while (state != STOP) {
        [[ordered]]
        select {
            // Receive button press.
            case c_fromButtons :> buttonPressed:
                if (buttonPressed == SW2) { state = STOP; }             // Enter STOP state.
                break;
            
            // Receive orientation.
            case fromAcc :> val:
                if (val == 1 && state == CONTINUE) { state = PAUSE; }   // Enter PAUSE state
                if (val == 0 && state == PAUSE) { state = CONTINUE; }   // Enter CONTINUE state
                break;
            
            // Data from subdistributor for processing rounds.
            case c_subDist[int i] :> val:                               // Signal that one distributor is ready.
                for (int i = 0; i < 4; i++) { edges[i] = 0; }           // Reseting variables.
                c_subDist[(i + 1) % 2] :> val;                          // Waiting for other subDist to be ready.

                // Switching LEDS off or on (Depending on the round).
                if (round % 2 == 0) {
                    leds <: OFF;
                }
                else {
                    leds <: GRNS;
                }
            
                if (round == RUNUNTIL ) { state = STOP; } // For testing.

                // Add time
                // This is to account for the overflow of the timing.
                if (previousRound != round) {
                    current = getCurrentTime();
                    if (current < start) {
                        current += 42.94967295;
                    }
                    totalTime += current - start;
                    previousRound = round;
                }
                start = getCurrentTime();

                // Sending the state to the sub distributor.
                if (state == CONTINUE) {
                    c_subDist[0] <: CONTINUE;
                    c_subDist[1] <: CONTINUE;
                }
                else if (state == STOP) {
                    c_subDist[0] <: STOP;
                    c_subDist[1] <: STOP;
                    leds <: BLU;
                }
                else if (state == PAUSE) {
                    c_subDist[0] <: 1;
                    c_subDist[1] <: 1;
                    leds <: RED;
                }

                // If CONTINUE, receive images edges from sub distributor to be assigned edges.
                if (state == CONTINUE) {
                    round++ ;                     // Increment Round Number.
                    for (int i = 0; i < IMHT; i ++ ){
                        // Receiving edges from each sub distributor.
                        c_subDist[0] :> edges[0];
                        c_subDist[0] :> edges[1];
                        c_subDist[1] :> edges[2];
                        c_subDist[1] :> edges[3];

                        // Assigning edges values to each edge.
                        edges[3] = assignRightEdge(edges[3],IMHT % 30, edges[0]);
                        edges[0] = assignLeftEdge(edges[3], IMHT % 30,  edges[0]);
                        edges[1] = assignRightEdge(edges[1], 30, edges[2]);
                        edges[2] = assignLeftEdge(edges[1], 30, edges[2]);

                        // This is an outlier case.
                        if (UINTARRAYWIDTH - SPLITWIDTH == 1) {
                            edges[3] = assignLeftEdge(edges[1], 30, edges[3]);
                            edges[2] = assignRightEdge(edges[2],IMHT % 30, edges[0]);
                        }

                        // Sends back the edges to the sub Distributor.
                        for (int j = 0; j < 2; j ++) {
                            c_subDist[0] <: edges[j];
                            c_subDist[1] <: edges[j+2];
                        }
                     }
                }
                // If state is STOP or CONTINUE.
                else { 
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0 ; j < UINTARRAYWIDTH; j ++) {
                            length = 30;
                            if (j == UINTARRAYWIDTH - 1) { length = IMWD % 30; }

                            // Receiving image from sub distributor.
                            if (j < SPLITWIDTH) { c_subDist[0] :> val; }
                            else { c_subDist[1] :> val; }

                            // Calculate the amount of live cells at current turn.
                            aliveCells = aliveCells + numberOfAliveCells(val, length);

                            if (state == STOP) {
                                // Splitting uint32_t into its constituent bits
                                // To be written out.
                                for (int l = 1 ; l < length + 1 ; l ++) {
                                    c_out <: getBit(val, l);
                                }
                            }
                        }
                    }
                    // Print status report.
                    printStatusReport(totalTime, round, aliveCells, state - 1);
                    aliveCells = 0;      // Reset number of cells.
                    
                    // Wait for state to change from pause.
                    while (state == PAUSE) {
                        fromAcc :> val;
                        if (val == 0) {
                            state = CONTINUE;
                        }
                    }
                    // If STOP, then turn off LEDS.
                    if (state == STOP) { leds <: OFF; }  // Turn OFF the green LED to indicate reading of the image has FINISHED.
                }
                break;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given an array of the state of workers, as 1 or 0.
// Returns the first available worker.
//
/////////////////////////////////////////////////////////////////////////////////////////
uchar findFreeWorker(uchar workers [NUMBEROFWORKERS]) {
    for (int i = 0; i < NUMBEROFWORKERS; i ++) {
        if (workers[i] == 0) {  //A free worker is found.
            return i;
        }
    }
    return -1; //If no workers are free.
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void subDistributor( chanend c_in,  chanend c_toWorker[n], unsigned n)
{
  uint32_t linePart[SPLITWIDTH][IMHT]; // Stores processing image.
  uint32_t copyPart[SPLITWIDTH][IMHT]; // Stores results.
  uchar readIn = 1;                    // Boolean, if reading in from main distributor.
  uchar sent = 0;                      // Boolean, if something is sent to workers.


  int edgesColsSent = 0;               // Edges sent from worker
  int edgesRowsSent = 0;               // Edges sent 

  int edgesRowsReceived = 0;           // Recieved from main distributor
  int edgesColsReceived = 0;           // Recieved from main distributor

  int workerEdgeColsReceived = 0;      // Received from worker
  int workerEdgeRowsReceived = 0;      // 

  int distColsReceived = 0;            // number of columns received from the distributor.
  int distRowsReceived = 0;            // numbers of rows received from the distributor

  int workerColsReceived = 0;          // number of columns received from workers
  int workerRowsReceived = 0;          //number of rows received from workers

  int workerColsSent = 0;              // number of columns sent to the worker.
  int workerRowsSent = 0;              // number of rows sent to the worker.

  int actualWidth = 0;                 // actual width of the array used.
  int val = 0;                         // input value from c_in or c_toWorkers.

  uchar workerState[NUMBEROFWORKERS];  // Store the state of the worker.
  uchar freeWorker = -1;               // Number of free workers.

  /*
   * index[j][i] for the workers
   * first column represents cols sent
   * second represent rows sent
   */
  int index[NUMBEROFWORKERS][2];

  uchar state = 0;                     // Boolean, for state.
  uchar nextTurn = 0;                  // Boolean, for next state.

  uchar workersWorking = 0;            // Number of workers starting to work

  // Initialise empty arrays
  for (int i = 0; i < NUMBEROFWORKERS; i ++) {
      for (int j = 0; j < 2; j ++) {
          index[i][j] = 0;
      }
      workerState[i] = 0;
  }

  // Getting actual width from main dsitributor
  c_in :> actualWidth;

  // Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, actualWidth );
  while (state != STOP) {
      if (actualWidth == 1 || actualWidth == 2) {
          if (edgesRowsReceived == IMHT) { readIn = 0; }                                                 // If finished read in from main.
          if (edgesRowsSent == IMHT && workerEdgeRowsReceived == IMHT && readIn == 0) { nextTurn = 1; }  // if finished processing current turn.
      }
      else {
          if (edgesRowsReceived == IMHT && distRowsReceived ==IMHT) { readIn = 0; }                     // if finish read in
          if (workerRowsSent == IMHT && edgesRowsSent == IMHT && workerEdgeRowsReceived == IMHT && workerRowsReceived == IMHT  && readIn == 0) { nextTurn = 1; } // finished processing current turn
      }
      
      // Distribute work to workers.
      if (nextTurn == 0 && workersWorking < NUMBEROFWORKERS) {
          freeWorker = findFreeWorker(workerState);
          //Work on edges if possible.
          if (edgesRowsSent <= edgesRowsReceived - 3 || (edgesRowsReceived == IMHT && edgesRowsSent < IMHT)) {
              index[freeWorker][1] = (edgesRowsSent + 1) % IMHT;
              edgesColsSent++;
              if (actualWidth == 1) {
                  index[freeWorker][0] = 0;
                  edgesRowsSent++;
              }
              else {
                  index[freeWorker][0] = (edgesColsSent % 2) * (actualWidth - 1);
                  if (edgesColsSent % 2 == 0) { edgesRowsSent++; }
              }
              sent = 1;
          }
          // Else work on the rest of the image.
          if (sent == 0 && actualWidth > 2) {
              if (workerColsSent < distRowsReceived - 2 * (actualWidth - 2) || (distRowsReceived == IMHT && workerRowsSent < IMHT)) {
                  index[freeWorker][0] = (workerColsSent) % (actualWidth - 2) + 1;
                  index[freeWorker][1] = (workerRowsSent + 1) % IMHT;
                  workerColsSent++;
                  if (workerColsSent % (actualWidth - 2) == 0) { workerRowsSent++; }
                  sent = 1;
              }
          }
          // Send image to worker (if available).
          if (sent == 1) {
              for (int x = 0; x < 3 ; x++) {
                  c_toWorker[freeWorker] <: linePart[index[freeWorker][0]][(index[freeWorker][1] - 1 + x + IMHT) % IMHT];
              }
              workerState[freeWorker] = 1;
              workersWorking ++;
              sent = 0;
          }
      }
      [[ordered]]
      select {
        // Case when receiving from the (main distributor).
        case c_in :> val:
            // Receiving image from main.
            if (readIn) {
                if (actualWidth == 1) {
                    linePart[0][edgesRowsReceived] = val;
                    edgesColsReceived ++;
                    edgesRowsReceived++;
                }
                else if (actualWidth == 2) {
                    linePart[(edgesColsReceived % 2)][edgesRowsReceived] = val;
                    edgesColsReceived ++;
                    if (edgesColsReceived % 2 == 0) { edgesRowsReceived++; }
                }
                else {
                    if ((edgesColsReceived + distColsReceived) % actualWidth == 0 || (edgesColsReceived + distColsReceived) % actualWidth == actualWidth - 1) {
                        linePart[(actualWidth - 1) * (edgesColsReceived % 2)][edgesRowsReceived] = val;
                        edgesColsReceived ++;
                        if (edgesColsReceived % 2 == 0) { edgesRowsReceived++; }
                    }
                    else {
                        linePart[(distColsReceived % (actualWidth- 2)) + 1][distRowsReceived] = val;
                        distColsReceived ++;
                        if (distColsReceived % (actualWidth - 2) == 0) { distRowsReceived ++; }
                    }
                }
            }
            // Receiving edges only.
            else {
                linePart[0][edgesRowsReceived] = val;
                c_in :> val;
                linePart[actualWidth - 1][edgesRowsReceived] = val;
                edgesColsReceived = edgesColsReceived + 2;
                edgesRowsReceived ++;
                if (edgesRowsReceived < IMHT) {                    // Sent more edges to main.
                    c_in <: linePart[0][edgesRowsReceived];
                    c_in <: linePart[(actualWidth - 1)][edgesRowsReceived];
                }
            }
            break;

        // When safe for worker to send back data.
        // Case when receiving from the work.
        case c_toWorker[int i] :> copyPart[index[i][0]][index[i][1]]:
            workersWorking = workersWorking - 1;
            workerState[i] = 0;

            // If received an edge.
            if (index[i][0] == 0 || index[i][0] == actualWidth - 1) {
                workerEdgeColsReceived ++;
                if (actualWidth == 1) {
                    workerEdgeRowsReceived ++;
                }
                else {
                    if (workerEdgeColsReceived % 2 == 0) { workerEdgeRowsReceived ++; }
                }
            }
            // If received an image part.
            else
            {
                workerColsReceived++;
                if (workerColsReceived % (actualWidth - 2) == 0) { workerRowsReceived ++; }
            }

            break;

        default:
            while (nextTurn) {
                c_in <: 1;                              // Letting main distributor know (this) is ready
                c_in :> val;                            // Receiving "state" from main.

                // Deciding what to do.
                if (val == 0)      { state = CONTINUE; }
                else if (val == 1) { state = PAUSE; }
                else if (val == 2) { state = STOP; }

                // When NOT paused.
                if (state == CONTINUE) {
                    // Assign edges to each part of the image.
                    for (int i = 0; i < IMHT; i++){
                        for (int j = 0; j < actualWidth; j++) {
                            val = copyPart[j][i];
                            if (j  < actualWidth - 1) {
                               val = assignRightEdge(val, 30, copyPart[j + 1][i]);
                            }
                            if (j > 0) {
                                val = assignLeftEdge(copyPart[j - 1][i], 30, val);
                            }
                            linePart[j][i] = val;
                        }
                    }

                    // Send the edges to be assign its edge cases.
                    c_in <: linePart[0][0];
                    c_in <: linePart[actualWidth - 1][0];
                }

                // Sending image to main.
                if (state == PAUSE || state == STOP) {
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0; j < actualWidth; j ++) {
                            c_in <: copyPart[j][i];

                        }
                    }
                }
                //Reset variables for next turn.
                if (state == CONTINUE) {
                    edgesColsSent = 0;
                    edgesRowsSent = 0;

                    edgesRowsReceived = 0;
                    edgesColsReceived = 0;

                    workerEdgeColsReceived =0;
                    workerEdgeRowsReceived =0;

                    nextTurn = 0;

                    workerColsReceived = 0;
                    workerRowsReceived = 0;
                    workerColsSent = 0;
                    workerRowsSent = 0;
                    workersWorking = 0;
                }
            }
            break;
      }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given the current "state" of the cell,
// and the count of the surrounding neighbours.
// Return the new state.
//
/////////////////////////////////////////////////////////////////////////////////////////
uchar deadOrAlive(uchar state, uchar count) {
    uchar newState = state;
    //If alive...
    if (state == 255) {
        if (count < 2 || count > 3) { newState = 0; }   //Now dead.
    }
    // If dead...
    else if (count == 3) { newState = 255; }            // Now alive.
    return newState;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Given a (uchar) input,
// Determine if is equal to 255
// Return 1, otherwise 0.
//
/////////////////////////////////////////////////////////////////////////////////////////
uchar isTwoFiveFive(uchar input) {
    if (input == 255) { return 1; }
    else { return 0; }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Worker that processes part of the image.
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker( chanend c_fromDist) {
    uint32_t lines[3];              //input from the distributor.
    uchar results[30];              //records the results.
    uchar count = 0;                //number of neighbours for each cell.
    uchar state = 0;                //the current state (alive or dead) of the cell.
    uint32_t output = 0;
    while (1) {
        for (int i = 0; i < 3; i++) { c_fromDist :> lines[i]; } //receiving work from distributors.
        for (int j = 1; j < 31; j++) {                          // goes through each bit in the input
            count = 0;
            state = 0;
            results[j - 1] = 0;
            for (int i = 0; i < 3; i++) {                       // goes through each row
                count = count + isTwoFiveFive(getBit(lines[i], j + 1));
                count = count + isTwoFiveFive(getBit(lines[i], j - 1));
                if (i != 1) {
                    count = count + isTwoFiveFive(getBit(lines[i], j));
                }
                else {
                    state = getBit(lines[i], j);
                }
            }
            results[j - 1] = deadOrAlive(state, count);         //assigns the result to uchar.
        }
        output = compress(results, 30);                         //compresses the results.
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
            if (x <= 10 && x >= -10) {
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

i2c_master_if i2c[1];                                               //interface to orientation

 chan c_inIO;
 chan c_outIO, c_control;                                            //extend your channel definitions here
 chan c_workers[NUMBEROFWORKERS];                                    // Worker channels (one for each worker)  for sub distributor 0.
 chan c_otherWorkers[NUMBEROFWORKERS];                               // Worker channels (one for each workder) for sub distributor 1.
 chan c_buttonsToDist, c_buttonsToData;                              // Button and LED channels.
 chan c_subDist[NUMBEROFSUBDIST];                                    // Channels for communicating between main distributor its slaves.

par {
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);                                  //server thread providing orientation data
    on tile[1]: orientation(i2c[0],c_control);                                         //client thread reading orientation data
    on tile[1]: DataInStream(infname, c_inIO, c_buttonsToData);                        //thread to read in a PGM image
    on tile[1]: DataOutStream(outfname, c_outIO);                                      //thread to write out a PGM image
    on tile[0]: mainDistributor(c_buttonsToDist, c_control, c_inIO, c_outIO, c_subDist, NUMBEROFSUBDIST);   //thread to coorinate work to coordinators.
    on tile[1]: subDistributor(c_subDist[0], c_workers, NUMBEROFWORKERS);              //thread to coordinate work on image
    on tile[0]: subDistributor(c_subDist[1], c_otherWorkers, NUMBEROFWORKERS);         //thread to coordinate work on image
    par (int i = 0; i < NUMBEROFWORKERS; i++){                                         //starting workers
        on tile[1]: worker(c_workers[i]);                                              // thread to do work on an image.
        on tile[0]: worker(c_otherWorkers[i]);                                         // thread to do work on an image.
    }

    on tile[0]: buttonListener(buttons,c_buttonsToData, c_buttonsToDist);              // Thread to listen for button presses.
  }

  return 0;
}
