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

#define NUMBEROFWORKERS 2         //number of workers
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

/*
 * assignLeftEdge assumes that left is already in the correct form).
 */
uint32_t assignLeftEdge(uint32_t left, uint32_t middle) {
    uint32_t val = middle;
    if (returnBitInt(left,31) == 255) {
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
        val = val | 0x00000001 << (31 - midLength);
        val = val | 0x00000001;
    }
    return val;
}
/*
 *
 */
uint32_t assignEdges(uint32_t left, uint32_t middle,uchar midLength, uint32_t right) {
    uint32_t val = middle;
    val = assignRightEdge(middle, midLength, right); //assign left depends on assign right.
    val = assignLeftEdge(left,middle);
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
          if (i == ceil(IMWD / 30)) {
              length = IMWD % 30;
          }
          row[i] = assignEdges(row[(i-1+UINTARRAYWIDTH) % UINTARRAYWIDTH], row[i],length, row[ (i + 1) %UINTARRAYWIDTH]);
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
    uchar pause = 0;
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
        length = 30;
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
                //recieve data from distributors
                break;
            case fromAcc :> pause:
                //Send signal to distributor.
                break;
            case (pause != 0) => c_subDist[int i] :> uint32_t val:
                if (rightDone + leftDone == 0) { //reset alive cells at the end of each round.
                    aliveCells = 0;
                    for (int i = 0; i < 4; i++) { //initialise edges.
                        edges[i] = 0;
                    }
                }
                if (i == 0) { //right most  distributor is ready.
                    rightDone = 1;
                    c_subDist[i] :> val;
                    aliveCells = aliveCells + val;
                }
                else { //left most  distributor is ready.
                    leftDone = 1;
                    c_subDist[i] :> val;
                    aliveCells = aliveCells + val;
                }
                if (rightDone + leftDone == 2) { //assign edges when both sub distributors are ready.
                    for (int i = 0; i < IMHT; i ++ ){
                        for (int j = 0; j < 4; j++ ) {// receiving edges
                            select {
                                case c_subDist[int l] :> uint32_t edge:
                                    uchar k = 0;
                                    uchar m = 2;
                                    if (l == 0) {
                                        edges[k] = edge;
                                        k ++;
                                    } else {
                                        edges[m] = edge;
                                        m ++;
                                    }
                                    break;
                            }

                        }
                        edges[3] = assignRightEdge(edges[3],length, edges[0]);
                        edges[0] = assignLeftEdge(edges[3], edges[0]);
                        edges[1] = assignRightEdge(edges[1], 30, edges[2]);
                        edges[2] = assignLeftEdge(edges[1], edges[2]);
                        for (int j = 0; j < 2; j ++) {
                            c_subDist[0] <: edges[j];
                            c_subDist[0] <: edges[j+2];
                        }
                    }
                    rightDone = 0;
                    leftDone = 0;
                    printf("done\n");
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

  uchar safe = 0; // safe to send to workers
  uchar pause = 0; // boolean for pause state
  uchar readIn = 1; //boolean for reading in files.
  uchar nextTurn = 0; //boolean for next Turn

  uint32_t actualWidth = 0; // actual width of the array used.
  uint32_t input = 0;

  /*
   * index[j][i] for the workers
   * first column represents cols sent
   * second represent rows sent
   */
  uchar index[NUMBEROFWORKERS][2];

  //initialise array
  for (int i = 0; i < NUMBEROFWORKERS; i ++) {
      for (int j = 0; j < 2; j ++) {
          index[i][j] = 0;
      }
  }

  uchar colsReceived = 0;   //index for the width of input array i
  uchar rowsReceived = 0;  //index for the height of input array j

  uchar colsSent = 0; //number of columns sent. l
  uchar rowsSent = 0; //number of rows sent. k

  uchar workersStarted = 0;


  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  c_in :> actualWidth;
  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  while (1) {
      if (rowsSent == IMHT) { nextTurn = 1; } //increment turn
      if (rowsReceived == IMHT) { readIn = 0; }
      // starts to work the workers.
      if (safe && workersStarted < NUMBEROFWORKERS) {
          for (int x = 0; x < 3 ; x++) {
              c_toWorker[workersStarted] <: linePart[colsSent][rowsSent - 1 + x + IMHT % IMHT];
          }
          colsSent ++;
          rowsSent ++;
          index[workersStarted][0] = colsSent % actualWidth;
          index[workersStarted][1] = rowsSent;
          workersStarted ++;
      }
      select {
        //case when receiving from the (main distributor).
        case c_in :> input:
            if (readIn) {
                linePart[(colsReceived + 1) % actualWidth][rowsReceived] = input;
                colsReceived ++;
                if ((colsReceived + 1) % actualWidth) { rowsReceived ++; } //increment height when i goes over the "edge";
                if (rowsReceived == IMHT && colsReceived == IMHT * actualWidth) {
                    readIn = 0; //finished readIn.
                }

                //Various if conditions for unsafe working of worker.
                if (rowsSent + 3 <= rowsReceived && rowsReceived < IMHT) { safe = 1; }
                else if (rowsReceived == IMHT) { safe = 1; }
                else { safe = 0; }
            }
            else if (nextTurn == 0) {
                if (input == 0) {
                    pause = 1;
                }
                else if (input == 1) {
                    pause = 0;
                }
            }
            break;
        //when safe for worker to send back data.
        //case when receiving from the work.
        case (safe) => c_toWorker[int i] :> uint32_t output:
            //copyPart[l][(k + 1) % IMHT] = output;
            if (nextTurn == 0) {
                for (int x = 0; x < 3 ; x++) {
                    c_toWorker[i] <: linePart[(index[i][0])][(index[i][1])];
                }
                index[i][0] = colsSent % actualWidth;
                index[i][1] = rowsSent;
                colsSent ++;
                if ((colsSent + 1) % actualWidth == 0) { rowsSent ++; }
                if (rowsSent == IMHT && colsSent == IMHT * actualWidth) {
                    nextTurn = 1; //finished readIn.
                }
            }
            break;
        default:
            if (nextTurn){
                //send edges cases when not paused.
                if (pause == 0) {
                    printf( "\nOne processing round completed...\n" );
                    for (int i = 0; i < IMHT; i++) {
                        for (int j = 0; j < actualWidth ; j++) {
                            printBinary(copyPart[j][i], 16);
                        }
                    }
                    c_in <: 1; //signalling done...
                    //logic for sending edges
                    for (int i = 0; i < IMHT; i++){
                        for (int j = 0; j < actualWidth; j++) {
                            if (j  < actualWidth - 1) {
                                linePart[j][i] = assignRightEdge(copyPart[j][i],30,copyPart[j + 1][i]);
                            }
                            if (j > 0) {
                                linePart[j][i] = assignLeftEdge(copyPart[j - 1][i], copyPart[j][i]);
                            }
                        }
                        c_in <: linePart[0][i];
                        c_in <: linePart[actualWidth - 1][i];
                        c_in :>linePart[0][i];
                        c_in :> linePart[actualWidth - 1][i];

                        //reset variables??
                    }
                }
                //send image to main distributor.
                if (pause) {
                    for (int i = 0; i < IMHT; i ++) {
                        for (int j = 0; j < actualWidth; j ++) {
                            c_in <: linePart[j][i];
                        }
                    }
                }
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

chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
chan c_workers[NUMBEROFWORKERS];     // Worker channels (one for each worker).
chan c_otherWorkers[NUMBEROFWORKERS];
chan c_buttonsToDist, c_DistToLEDs, c_buttonsToData;  // Button and LED channels.
chan c_subDist[NUMBEROFSUBDIST];

par {
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]: orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0]: DataInStream(infname, c_inIO, c_buttonsToData);          //thread to read in a PGM image
    on tile[0]: DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
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
