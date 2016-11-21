// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define IMHT 16    // Image height.
#define IMWD 16    // Image width.
#define SEGHT 4   // Number of rows to analyse in each farmed segment.

#define MAX_ROUNDS 2  // Maxiumum number of rounds to be processed (uncomment relevant if statement in Master Distributor).

#define WORKERS 4  // Total number of workers processing the image (must be an even number).

// Signals sent from Master to Slave Distributors.
#define CONTINUE 0
#define PAUSE    1
#define STOP     2

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

typedef unsigned char uchar;  // Using uchar as shorthand.

// Interface ports to orientation.
on tile[0]: port p_scl = XS1_PORT_1E;
on tile[0]: port p_sda = XS1_PORT_1F;
// Register addresses for orientation.
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

// Image paths.
char infname[] = "test.pgm";      // Input image path
char outfname[] = "testout.pgm";  // Output image path

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


/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
uchar DataInStream(chanend c_out) {
    int res;           // Result of reading in a PGM file.
    uchar line[IMWD];  // A line to be read in.
    printf( "DataInStream: Start...\n" );

    // Open PGM file.
    res = _openinpgm(infname, IMWD, IMHT);
    if (res) {
        printf("DataInStream: Error openening %s\n.", infname);
        return -1;
    }

    // Read image line-by-line and send byte by byte to channel c_out.
    for (int y = 0; y < IMHT; y++) {
        _readinline(line, IMWD);
        //printf("[%2.1d]", y);
        for (int x = 0; x < IMWD; x++) {
            c_out <: line[x];
        //    printf("-%4.1d ", line[x]);
        }
        //printf("\n");
    }

    // Close PGM image file.
    _closeinpgm();
    printf("DataInStream: Done...\n");
    return 0;
}


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
           rounds, liveCells, IMHT*IMWD, time, WORKERS);
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Distributor that splits the image in two and farms out each half to slave distributors
// that coordinate work on their section with worker threads.
//
/////////////////////////////////////////////////////////////////////////////////////////
void masterDistributor(chanend c_fromButtons, chanend c_toLEDs, chanend c_in, chanend c_out, chanend fromAcc, chanend c_toSlave[2]) {
    int buttonPressed;        // The button pressed on the xCore-200 Explorer.
    int tilted;               // Value received when the board orientation is changed.
    uchar edges[4][IMHT];
    uchar pixel;

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

    // Read in the image from DataInStream.
    printf( "Reading in original image...\n" );
    //printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n");
    c_toLEDs <: GRN;  // Turn ON the green LED to indicate reading of the image has STARTED.
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD; x++ ) {
            c_in :> pixel;
            // Split the image between the slave distributors.
            if   (x < IMWD/2) c_toSlave[0] <: pixel;
            else              c_toSlave[1] <: pixel;
            // Identify and store the overlapping edges.
            if      ( x  == 0)      edges[0][y] = pixel;
            else if (x+1 == IMWD/2) edges[1][y] = pixel;
            else if ( x  == IMWD/2) edges[2][y] = pixel;
            else if (x+1 == IMWD)   edges[3][y] = pixel;
        }
    }
    c_toLEDs <: OFF;  // Turn OFF the green LED to indicate reading of the image has FINISHED.

    // SEND EDGES FOR THE FIRST ROUND.
    for (int y = 0; y < IMHT; y++) {
        c_toSlave[0] <: edges[3][y];
        c_toSlave[0] <: edges[2][y];
        c_toSlave[1] <: edges[1][y];
        c_toSlave[1] <: edges[0][y];
    }

    // Processing the rounds.
    printf("\nProcessing...\n");
    int rounds = 0;                     // The number of rounds processed.
    int running = 1;                    // Whether to keep running.
    double start = getCurrentTime();    // Start time of processing.
    double current = getCurrentTime();  // Time after processing a round.
    int liveCells[2];                   // The number of live cells in the current image.

    while (running) {

        select {
            // When SW2 button is pressed, stop processing, print and save the current image.
            case c_fromButtons :> buttonPressed:
                if (buttonPressed == SW2) {
                    printf("Saving new image...\n");
                    // SEND SIGNAL TO DISTRIBUTORS TO STOP AND SEND THEIR IMAGE.
                    c_toSlave[0] <: STOP;
                    c_toSlave[1] <: STOP;

                    c_toSlave[0] :> liveCells[0];
                    c_toSlave[1] :> liveCells[1];
                    printStatusReport(start, current, rounds, liveCells[0]+liveCells[1], 1);

                    c_toLEDs <: BLU;  // Turn ON the blue LED to indicate export of the image has STARTED.
                    //printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n");
                    for (int y = 0; y < IMHT; y++) {
                        //printf("[%2.1d]", y);
                        for (int x = 0; x < IMWD/2; x++) {
                            c_toSlave[0] :> pixel;
                            c_out <: pixel;
                        //    printf( "-%4.1d ", pixel);
                        }
                        for (int x = IMWD/2; x < IMWD; x++) {
                            c_toSlave[1] :> pixel;
                            c_out <: pixel;
                        //    printf( "-%4.1d ", pixel);
                        }
                        //printf("\n");
                    }

                    c_toLEDs <: OFF;  // Turn OFF the blue LED to indicate export of the image has FINISHED.
                    running = 0;
                }
                break;

            // When the board is vertical, pause the state and print a status report.
            // Resume processing when horizontal again.
            case fromAcc :> tilted:
                printf("Board vertical\n");
                // Board vertical.
                c_toLEDs <: RED;  // Turn ON the red LED to indicate that the state is PAUSED.

                // SEND SIGNAL TO DISTRIBUTORS THAT PROCESSING IS PAUSED.
                c_toSlave[0] <: PAUSE;
                c_toSlave[1] <: PAUSE;

                // RECEIVE NUMBER OF LIVE CELLS IN EACH SLAVE DISTRIBUTOR IMAGE.
                c_toSlave[0] :> liveCells[0];
                c_toSlave[1] :> liveCells[1];

                // PRINT STATUS REPORT.
                printStatusReport(start, current, rounds, liveCells[0]+liveCells[1], 0);

                // Board horizontal.
                fromAcc :> tilted;
                printf("Board horizontal\n");

                // SEND SIGNAL TO DISTRIBUTORS TO CONTINUE.
                c_toSlave[0] <: CONTINUE;
                c_toSlave[1] <: CONTINUE;
                c_toLEDs <: OFF;  // Turn OFF the red LED to indicate that the state is UNPAUSED.
                break;

            // Otherwise, continue processing the image.
            default:
                //if (rounds < MAX_ROUNDS) {  // UNCOMMENT THIS WHEN PROCESSING A SPECIFIED NUMBER OF ROUNDS.
                    // Alternate the separate green light on and off each round while processing rounds.
                    if (rounds % 2 == 0) {
                        c_toLEDs <: GRNS;
                    }
                    else {
                        c_toLEDs <: OFF;
                    }

                    // SEND SIGNAL TO DISTRIBUTORS PROCESS ANOTHER ROUND.
                    c_toSlave[0] <: CONTINUE;
                    c_toSlave[1] <: CONTINUE;

                    // RECEIVE NEW EDGES FROM EACH DISTRIBUTOR.
                    for (int y = 0; y < IMHT; y++) {
                        c_toSlave[0] :> edges[0][y];
                        c_toSlave[0] :> edges[1][y];
                        c_toSlave[1] :> edges[2][y];
                        c_toSlave[1] :> edges[3][y];
                    }

                    // PASS NEW EDGES RECEIVED FROM ONE DISTRIBUTOR TO THE OTHER.
                    for (int y = 0; y < IMHT; y++) {
                        c_toSlave[0] <: edges[3][y];
                        c_toSlave[0] <: edges[2][y];
                        c_toSlave[1] <: edges[1][y];
                        c_toSlave[1] <: edges[0][y];
                    }

                    current = getCurrentTime();
                    rounds++;
                    printf("ROUND %d COMPLETE\n\n", rounds);
                //}
                //else {
                //    c_toLEDs <: OFF;
                //}
                break;
        }
    }

}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Counts the number of live cells in an slave distributor image.
//
/////////////////////////////////////////////////////////////////////////////////////////
int countLiveCells(uchar image[IMWD/2 + 2][IMHT]) {
    int count = 0;
    for (int y = 0; y < IMHT; y++) {
        // Skip the first and last columns as they are edges provided for info only.
        for (int x = 1; x < (IMWD/2 + 1); x++) {
            if (image[x][y] == 255) {
                count ++;
            }
        }
    }
    return count;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Slave Distributor that farms out parts of its half of the image to worker threads who
// process the image according to the rules of the Game of Life!
//
/////////////////////////////////////////////////////////////////////////////////////////
void slaveDistributor(chanend c_fromMaster, chanend c_toWorker[n], unsigned n, int distNum) {
    uchar image[IMWD/2 + 2][IMHT];     // The whole image being processed.
    uchar newImage[IMWD/2 + 2][IMHT];  // The whole image being processed.
    uchar pixel;                       // A single pixel being sent to a worker.
    int distWD = IMWD/2 + 2;

    // Read in the image from MasterDistributor.
    for (int y = 0; y < IMHT; y++) {
        for (int x = 1; x < distWD-1; x++ ) {
            c_fromMaster :> image[x][y];
        }
    }
    // Read in the overlapping edges from MasterDistributor.
    for (int y = 0; y < IMHT; y++) {
        c_fromMaster :> image[0][y];
        c_fromMaster :> image[distWD-1][y];
    }

    int workerRow[WORKERS/2];  // The rows that the workers are currently analysing.

    // Processing the rounds.
    int running = 1;
    while (running) {

        int signal;  // Signal received from the MasterDistributor advising what to do next.
        c_fromMaster :> signal;
        // Process another round.
        if (signal == CONTINUE) {
            // SEGHT rows are sent to a worker at a time to analyse (FARMING PARALLELISM).

            // SENDING THE INITIAL ROWS TO EACH WORKER.
            int y = 0;             // Row reference.
            int w = 0;             // The worker receiving a pixel.
            int segmentsSent = 0;  // Total number of image segments sent to the workers.

            while (w < WORKERS/2) {
                for (int y2 = 0; y2 < SEGHT + 2; y2++) {
                    for (int x = 0; x < distWD; x++) {
                        pixel = image[x][(((y + IMHT) - 1) % IMHT)];
                        c_toWorker[w] <: pixel;
                    }
                    if (y2 == 0) {
                        workerRow[w] = y;
                    }
                    y++;
                }
                segmentsSent++;
                w++;
                y -= 2;
                if (y == IMHT) break;
            }

            // RECEIVING UPDATES AND FARMING OUT MORE ROWS.
            int segmentsReceived = 0;
            while (segmentsReceived < IMHT / SEGHT) {
                select {
                    // Processed pixel received from worker i.
                    case c_toWorker[int i] :> pixel:
                        // Update the image with new pixel values.
                        newImage[1][workerRow[i]] = pixel;
                        for (int y2 = 0; y2 < SEGHT; y2++) {
                            for (int x = 1; x < distWD-1; x++) {
                                if (y2 == 0 && x == 1) x = 2;  // First pixel already added.
                                c_toWorker[i] :> pixel;
                                newImage[x][workerRow[i]+y2] = pixel;
                            }
                        }
                        segmentsReceived++;

                        // If there are rows still to complete, send more.
                        if (segmentsSent < IMHT / SEGHT) {
                            for (int y2 = 0; y2 < SEGHT + 2; y2++) {
                                for (int x = 0; x < distWD; x++) {
                                    pixel = image[x][(((y + IMHT) - 1) % IMHT)];
                                    c_toWorker[i] <: pixel;
                                }
                                if (y2 == 0) {
                                    workerRow[i] = y;
                                }
                                y++;
                            }
                            segmentsSent++;
                            y -= 2;
                        }
                        break;
                }
            }
            // Send new edges for other distributor to MasterDistributor.
            for (int y = 0; y < IMHT; y++) {
                c_fromMaster <: newImage[1][y];
                c_fromMaster <: newImage[distWD-2][y];
            }
            // Receive new edges from other distributor via MasterDistributor.
            for (int y = 0; y < IMHT; y++) {
                c_fromMaster :> newImage[0][y];
                c_fromMaster :> newImage[distWD-1][y];
            }
            // Copy newImage to image in preparation for the next round.
            memcpy(image, newImage, sizeof(uchar) * IMHT * distWD);

        }

        // Pause processing and send back the number of live cells in the current image.
        else if (signal == PAUSE) {
            c_fromMaster <: countLiveCells(image);
            c_fromMaster :> int goSignal;
        }

        // Stop processing rounds and send back the current image.
        else if (signal == STOP) {
            c_fromMaster <: countLiveCells(image);
            for (int y = 0; y < IMHT; y++) {
                // Skip the first and last columns as they are edges provided for info only.
                for (int x = 1; x < distWD-1; x++) {
                    c_fromMaster <: image[x][y];
                }
            }
            running = 0;
        }

    }

}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Determines if a cell should be dead alive based on the number of alive cells
// surrounding it.
//
// LOGIC FOR IF CELL WILL CHANGE:
// • any live cell with fewer than two live neighbours dies.
// • any live cell with two or three live neighbours is unaffected.
// • any live cell with more than three live neighbours dies.
// • any dead cell with exactly three live neighbours becomes alive.
//
/////////////////////////////////////////////////////////////////////////////////////////
uchar deadOrAlive(uchar cell, int count) {
    uchar newStatus = cell;
    // If currently alive
    if (cell == 255) {
        if (count < 2 || count > 3) {
            newStatus = 0;  // Now dead.
        }
    }
    // If dead
    else if (count == 3) {
        newStatus = 255;  // Now alive.
    }

    return newStatus;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Checks the 8 surrounding cells in a worker image segment and counts how many are
// alive (cell value 255).
//
/////////////////////////////////////////////////////////////////////////////////////////
int aliveSurroundingCells(int x, int y, uchar image[IMWD/2 + 2][SEGHT + 2]) {
    int count = 0;  // The number of alive cells.
    for (int j = 0; j < 3; j++) {
        for (int i = 0; i < 3; i++) {
            if (i == 1 && j == 1) {  // Ignore the middle cell.
                i++;
            }
            if (image[x + i - 1][(y + j - 1 + IMHT) % IMHT] == 255) {
                count++;
            }
        }
    }

    return count;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Waits for the specified number of seconds.  Used to help show that the OS prioitises
// some worker threads on the same tile in select statements.
//
/////////////////////////////////////////////////////////////////////////////////////////
void waitForSeconds(unsigned int seconds) {
    timer t;
    unsigned int interval;
    unsigned int period = 100000000 * seconds;  // Period of one second.
    t :> interval;
    interval += period;
    t when timerafter (interval) :> void;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Worker that processes part of the image.
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker(chanend c_fromDist) {
    uchar image[IMWD/2 + 2][SEGHT + 2];  // The segment of the whole image that the worker will process.
    uchar pixel;                         // A single pixel in the image.
    int segWD = IMWD/2 + 2;              // Width of a worker image segment.

    while (1) {

        // READ IN IMAGE SEGMENT FROM DISTRIBUTOR.
        for (int y = 0; y < SEGHT + 2; y++) {
            for (int x = 0; x < segWD; x++) {
                c_fromDist :> pixel;
                image[x][y] = pixel;
            }
        }

        // Wait for a second to allow all workers to contribute evenly.
        // Used to prove that the OS prioritises some threads over others in select statements.
        //waitForSeconds(1);

        // ANALYSE IMAGE SEGMENT FOR POTENTIAL CHANGES FOR NEXT ROUND.
        // Skip the top and bottom rows as they are edges provided for info only.
        for (int y = 1; y < SEGHT + 1; y++) {
            // Skip the first and last columns as they are edges provided for info only.
            for (int x = 1; x < segWD-1; x++) {
                // Check the number of surrounding alive cells.
                int count = aliveSurroundingCells(x, y, image);

                // Check the cells new mortality status.
                uchar newStatus = deadOrAlive(image[x][y], count);

                // Send the cell's new status back to the distributor.
                c_fromDist <: newStatus;
            }
        }
    }

}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(chanend c_in) {
    int res;
    uchar line[IMWD];

    //Open PGM file.
    printf("DataOutStream: Start...\n" );
    res = _openoutpgm( outfname, IMWD, IMHT );
    if(res) {
        printf( "DataOutStream: Error opening %s\n.", outfname );
        return;
    }

    //Compile each line of the image and write the image line-by-line.
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD; x++) {
            c_in :> line[x];
        }
        _writeoutline(line, IMWD);
        //printf( "DataOutStream: Line written...\n" );
    }

    // Close the PGM image.
    _closeoutpgm();
    printf("\nDataOutStream: Done...\n");
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
    i2c_master_if i2c[1];  // Interface to orientation

    chan c_inIO, c_outIO, c_control;                         // IO and orientation channels.
    chan c_masterToSlave[2];                                 // Channels between Master and Slave distributors.
    chan c_workersZero[WORKERS/2], c_workersOne[WORKERS/2];  // Worker channels (one for each worker).
    chan c_buttonsToDist, c_DistToLEDs;                      // Button and LED channels.

    par {
        // Only work on tile[0].
        on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);      // Server thread providing orientation data.
        on tile[0]: buttonListener(buttons, c_buttonsToDist);  // Thread to listen for button presses.
        on tile[0]: showLEDs(leds, c_DistToLEDs);              // Thread to process LED change requests.

        on tile[1]: orientation(i2c[0],c_control);  // Client thread reading orientation data.
        on tile[1]: DataInStream(c_inIO);           // Thread to read in a PGM image.
        on tile[1]: DataOutStream(c_outIO);         // Thread to write out a PGM image.

        // DISTRIBUTOR THREADS: Threads to coordinate work on image (image processes much faster if on same tile as workers).
        on tile[0]: masterDistributor(c_buttonsToDist, c_DistToLEDs, c_inIO, c_outIO, c_control, c_masterToSlave);
        on tile[0]: slaveDistributor(c_masterToSlave[0], c_workersZero, WORKERS/2, 0);
        on tile[1]: slaveDistributor(c_masterToSlave[1], c_workersOne, WORKERS/2, 1);

        // WORKER THREADS: Threads to do work on an image.
        par (int i = 0; i < WORKERS/2; i++) {
            on tile[0]: worker(c_workersZero[i]);
        }
        par (int i = 0; i < WORKERS/2; i++) {
            on tile[1]: worker(c_workersOne[i]);
        }

    }

  return 0;
}
