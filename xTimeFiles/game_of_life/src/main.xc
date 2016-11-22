// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define IMHT 64    // Image height.
#define IMWD 64    // Image width.

#define MAX_ROUNDS 1  // Maxiumum number of rounds to be processed.

#define WORKERS 4  // Total number of workers processing the image.

// Worker Types.
#define SINGLE 0   // Worker that processes an image all on its own!
#define LEFT   1   // Worker that processes the left-most segment of an image.
#define CENTRE 2   // Worker that processes one of the centre segments of an image.
#define RIGHT  3   // Worker that processes the right-most segment of an image.

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
char infname[] = "64x64.pgm";      // Input image path
char outfname[] = "64x64out(1).pgm";  // Output image path

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
uchar DataInStream(char infname[], chanend c_out) {
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
            //printf("-%4.1d ", line[x]);
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
// Counts the number of live cells in an image.
//
/////////////////////////////////////////////////////////////////////////////////////////
int countLiveCells(uchar image[IMWD][IMHT]) {
    int count = 0;
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD; x++) {
            if (image[x][y] == 255) {
                count ++;
            }
        }
    }
    return count;
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
void printStatusReport(double start, double current, int rounds, uchar image[IMWD][IMHT], int final) {
    int alive = countLiveCells(image);  // The number of live cells in the image.
    double time = current - start;      // Total time elapsed.

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
           rounds, alive, IMHT*IMWD, time, WORKERS);
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Distributor that farms out parts of the image to worker threads who process the image
// according to the rules of the Game of Life!
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_fromButtons, chanend c_toLEDs, chanend c_in, chanend c_out, chanend fromAcc, chanend c_toWorker[n], unsigned n) {
    uchar image[IMWD][IMHT];  // The whole image being processed.
    uchar pixel;              // A single pixel being sent to a worker.
    int buttonPressed;        // The button pressed on the xCore-200 Explorer.
    int tilted;               // Value received when the board orientation is changed.

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
    printf( "Populating image array...\n" );
    //printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n");
    c_toLEDs <: GRN;  // Turn ON the green LED to indicate reading of the image has STARTED.
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD; x++ ) {
            c_in :> image[x][y];
        }
    }
    c_toLEDs <: OFF;  // Turn OFF the green LED to indicate reading of the image has FINISHED.

    // Processing the rounds.
    printf("\nProcessing...\n");
    int rounds = 0;                     // The number of rounds processed.
    int running = 1;                    // Whether to keep running.
    double start = getCurrentTime();    // Start time of processing.
    double current = getCurrentTime();  // Time after processing a round.

    while (running) {

        select {
            // When SW2 button is pressed, stop processing, print and save the current image.
            case c_fromButtons :> buttonPressed:
                if (buttonPressed == SW2) {
                    c_toLEDs <: BLU;  // Turn ON the blue LED to indicate export of the image has STARTED.
                    printStatusReport(start, current, rounds, image, 1);
                    //printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n");
                    for (int y = 0; y < IMHT; y++) {
                        //printf("[%2.1d]", y);
                        for (int x = 0; x < IMWD; x++) {
                            c_out <: image[x][y];
                            //printf( "-%4.1d ", image[x][y]);
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
                // Board vertical.
                c_toLEDs <: RED;  // Turn ON the red LED to indicate that the state is PAUSED.
                printStatusReport(start, current, rounds, image, 0);

                // Board horizontal.
                fromAcc :> tilted;
                c_toLEDs <: OFF;  // Turn OFF the red LED to indicate that the state is UNPAUSED.
                break;

            // Otherwise, continue processing the image.
            default:
                if (rounds < MAX_ROUNDS) {  // UNCOMMENT THIS WHEN PROCESSING A SPECIFIED NUMBER OF ROUNDS.
                    // Alternate the separate green light on and off each round while processing rounds.
                    if (rounds % 2 == 0) {
                        c_toLEDs <: GRNS;
                    }
                    else {
                        c_toLEDs <: OFF;
                    }

                    // SENDING THE IMAGE TO THE WORKERS.
                    // The image is split vertically (GEOMETRIC PARALLELISM).
                    for (int y = 0; y < IMHT; y++) {
                        int fst = 1;  // Segment FIRST row counter.
                        int lst = 1;  // Segment LAST row counter.

                        for (int x = 0; x < IMWD+2; x++) {
                            //pixel = image[x][y];  // A single pixel in the image.
                            pixel = image[(((x + IMWD) - 1) % IMWD)][y];

                            // When only a single worker, send the pixels in sequence to the single worker.
                            //if (WORKERS == 1) {
                            //    c_toWorker[0] <: pixel;
                            //}

                            // When more than 1 worker, the boundaries between worker segments need sending to multiple workers.
                            //else {
                                // First row of each worker segment.
                                if ((x != IMWD+1) && (x!= 1) && ((x-1) % (IMWD / WORKERS) == 0)) {
                                    c_toWorker[((fst-1) + WORKERS) % WORKERS] <: pixel;
                                    c_toWorker[( fst    + WORKERS) % WORKERS] <: pixel;
                                    printf("(%d,%d) -> [%d] & [%d]\n", x, y, ((fst-1) + WORKERS) % WORKERS, (fst + WORKERS) % WORKERS);
                                    fst++;
                                }
                                // Last row of each worker segment.
                                else if ((x!=0) && (x!=IMWD) && (x % (IMWD / WORKERS) == 0)) {
                                    c_toWorker[((lst-1) + WORKERS) % WORKERS] <: pixel;
                                    c_toWorker[( lst    + WORKERS) % WORKERS] <: pixel;
                                    printf("(%d,%d) -> [%d] & [%d]\n", x, y, ((lst-1) + WORKERS) % WORKERS, (lst + WORKERS) % WORKERS);
                                    lst++;
                                }
                                // Remainging non-boundary pixels then split between the workers.
                                else {
                                    for (int i = 0; i < WORKERS; i++) {
                                        if (x < ((i+1)*IMWD/WORKERS)) {
                                            c_toWorker[i] <: pixel;
                                            printf("(%d,%d) -> [%d]\n", x, y, i);
                                            break;
                                        }
                                    }
                                }
                            //}
                        }

                    }
                    printf("here?\n");

                    // RECEIVING UPDATES FROM THE WORKERS.
                    int x[WORKERS];  // Each workers x coordinate to update in the new image.
                    int y[WORKERS];  // Each workers y coordinate to update in the new image.
                    for (int i = 0; i < WORKERS; i++) {
                        x[i] = i*IMWD/WORKERS;
                        y[i] = 0;
                    }

                    int workerRows = 0;  // Total number of rows completed by all workers.
                    while (workerRows < WORKERS * IMHT) {
                        select {
                            // Processed pixel received from worker i.
                            case c_toWorker[int i] :> pixel:
                                image[x[i]][y[i]] = pixel;
                                x[i]++;
                                if (x[i] == (i+1)*IMWD/WORKERS) {
                                    x[i] = i*IMWD/WORKERS;
                                    y[i]++;
                                    workerRows++;
                                }
                                break;
                        }
                    }
                    current = getCurrentTime();
                    rounds++;
                }
                else {
                    c_toLEDs <: OFF;
                }  // END OF MAX_ROUNDS IF STATEMENT.
                break;
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
int aliveSurroundingCells(int x, int y, uchar image[IMWD/WORKERS + 2][IMHT]) {
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
// Worker that processes part of the image.
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker(chanend c_fromDist, int workerType) {
    uchar image[IMWD/WORKERS + 2][IMHT];  // The segment of the whole image that the worker will process.
    uchar pixel;                          // A single pixel in the image.
    int segWD = IMWD/WORKERS + 2;         // The width of the worker segment.

    while (1) {

        for (int y = 0; y < IMHT; y++) {
            for (int x = 0; x < segWD; x++) {
                c_fromDist :> pixel;
                image[x][y] = pixel;
            }
        }
        /* READ IN IMAGE SEGMENT FROM DISTRIBUTOR.
        // Worker that processes the image all on its own!
        if (workerType == SINGLE) {
            for (int y = 0; y < IMHT; y++) {
                for (int x = 0; x < IMWD; x++) {
                    c_fromDist :> pixel;
                    image[x+1][y] = pixel;
                    // First column also goes at the end.
                    if (x == 0) {
                        image[segWD - 1][y] = pixel;
                    }
                    // Last column also goes at the start.
                    else if (x == IMWD-1) {
                        image[0][y] = pixel;
                    }
                }
            }
        }
        // Worker that processes the LEFT-MOST segment of the image.
        else if (workerType == LEFT) {
            for (int y = 0; y < IMHT; y++) {
                for (int x = 0; x < segWD; x++) {
                    // Gets the last column (of the whole image) last; puts it in column 0.
                    if (x == segWD - 1) {
                        c_fromDist :> image[0][y];
                    }
                    // x+1 because the column 0 arrives last.
                    else {
                        c_fromDist :> image[x+1][y];
                    }
                }
            }
        }
        // Worker that processes a CENTRE segment of the image.
        else if (workerType == CENTRE) {
            for (int y = 0; y < IMHT; y++) {
                for (int x = 0; x < segWD; x++) {
                    c_fromDist :> image[x][y];
                }
            }
        }
        // Worker that processes the RIGHT-MOST segment of the image.
        else if (workerType == RIGHT) {
            for (int y = 0; y < IMHT; y++) {
                for (int x = 0; x < segWD; x++) {
                    // get the first column (of the whole image) first; puts it at the end.
                    if (x == 0) {
                        c_fromDist :> image[segWD - 1][y];
                    }
                    // x-1 because the last column arrives first.
                    else {
                        c_fromDist :> image[x-1][y];
                    }
                }
            }
        }*/

        // ANALYSE IMAGE SEGMENT FOR POTENTIAL CHANGES FOR NEXT ROUND.
        for (int y = 0; y < IMHT; y++) {
            // Skip the first and last columns as they are boundaries provided for info only.
            for (int x = 1; x < (segWD - 1); x++) {
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
void DataOutStream(char outfname[], chanend c_in) {
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
    i2c_master_if i2c[1];                // Interface to orientation

    chan c_inIO, c_outIO, c_control;     // IO and orientation channels.
    chan c_workers[WORKERS];             // Worker channels (one for each worker).
    chan c_buttonsToDist, c_DistToLEDs;  // Button and LED channels.

    par {
        on tile[0]: orientation(i2c[0],c_control);             // Client thread reading orientation data.
        on tile[0]: DataInStream(infname, c_inIO);             // Thread to read in a PGM image.
        on tile[0]: DataOutStream(outfname, c_outIO);          // Thread to write out a PGM image.
        // Only work on tile[0].
        on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);      // Server thread providing orientation data.
        on tile[0]: buttonListener(buttons, c_buttonsToDist);  // Thread to listen for button presses.
        on tile[0]: showLEDs(leds, c_DistToLEDs);              // Thread to process LED change requests.

        // Thread to coordinate work on image (image processes much faster if on same tile as workers).
        on tile[1]: distributor(c_buttonsToDist, c_DistToLEDs, c_inIO, c_outIO, c_control, c_workers, WORKERS);

        // Worker threads that do work on an image.

        // SINGLE WORKER.
        //on tile[1]: worker(c_workers[0], SINGLE);

        // MULTIPLE WORKERS
        on tile[1]: worker(c_workers[0], LEFT);
            par (int i = 1; i < WORKERS-1; i++) {
                on tile[1]: worker(c_workers[i], CENTRE);
            }
        on tile[1]: worker(c_workers[WORKERS-1], RIGHT);

    }

  return 0;
}
