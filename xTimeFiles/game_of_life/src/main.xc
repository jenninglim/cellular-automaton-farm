// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define IMHT 16  // Image height.
#define IMWD 16  // Image width.

typedef unsigned char uchar;  // Using uchar as shorthand.

port p_scl = XS1_PORT_1E;     // Interface ports to orientation.
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E          // Register addresses for orientation.
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6


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
        printf( "DataInStream: Error openening %s\n.", infname );
        return -1;
    }

    // Read image line-by-line and send byte by byte to channel c_out.
    for (int y = 0; y < IMHT; y++) {
        _readinline(line, IMWD);
        if (y != 0) printf("[%2.1d]", y);
        for (int x = 0; x < IMWD; x++) {
            c_out <: line[x];
            printf("-%4.1d ", line[x]); // Show image values.
        }
        printf("\n");
    }

    // Close PGM image file.
    _closeinpgm();
    printf("DataInStream: Done...\n");
    return 0;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Distributor that farms out parts of the image to worker threads who the Game of Life!
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend c_toWorker[n], unsigned n) {
    uchar pixel;                 // A single pixel being read in.

    // Start up and wait for tilting of the xCore-200 Explorer.
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for Board Tilt...\n" );
    fromAcc :> int value;

    // Construct the image pixel by pixel.
    printf( "Populating image arrays...\n" );
    printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n[ 0]");
    for (int y = 0; y < IMHT; y++) {       // Go through all lines.
        for( int x = 0; x < IMWD; x++ ) {  // Go through each pixel per line.
            c_in :> pixel;           // Read the pixel value.
            if (x < (IMWD / 2)) {
                c_toWorker[0] <: pixel;
            }
            else {
                c_toWorker[1] <: pixel;
            }
        }
    }
    printf("\n");

    // Populate newImage with the updated values.
    uchar newImage[IMWD][IMHT];  // The image after processing a round.
    int x0 = 0;
    int y0 = 0;
    int x1 = IMWD/2;
    int y1 = 0;
    //int filled = 0;
    while (x0 < IMWD/2 && y0 < IMHT && x1 < IMWD && y1 < IMHT) {
        //printf("Starting newImage?\n");
        select {
            case c_toWorker[0] :> pixel:
                //if (y0==15) {
                    //printf("from 0: (%d,%d) = %d\n", x0, y0, pixel);
                //}
                newImage[x0][y0] = pixel;
                x0++;
                if (x0 == IMWD/2) {
                    x0 = 0;
                    y0++;
                }
                break;
            case c_toWorker[1] :> pixel:
                //if (y1 == 15) {
                //    printf("from 1: (%d,%d) = %d\n", x1, y1, pixel);
                //}
                newImage[x1][y1] = pixel;
                x1++;
                if (x1 == IMWD) {
                    x1 = IMWD/2;
                    y1++;
                }
                break;
        }
        //if (x0 == IMWD/2 && y0 == IMHT && x1 == IMWD && y1 == IMHT) {
        //    filled = 1;
        //}
    }

    // Print and save the pixel.
    printf("Processing...\n");
    printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n");
    for (int y = 0; y < IMHT; y++) {
        printf("[%2.1d]", y);
        for (int x = 0; x < IMWD; x++) {
            c_out <: newImage[x][y];
            printf( "-%4.1d ", newImage[x][y]);
        }
        printf("\n");
    }
    printf("\n");

    printf( "One processing round completed...\n" );
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Worker that processes part of the image.
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker(chanend c_fromDist, int n) {
    uchar image[IMWD/2][IMHT];
    //printf("Worker %d populating...\n", n);
    // Reading in the worker's part of the image.
    for (int y = 0; y < IMHT; y++) {       // Go through all lines.
        for( int x = 0; x < (IMWD/2); x++ ) {  // Go through each pixel per line.
            c_fromDist :> image[x][y];           // Read the pixel value.
        }
    }
    //printf("Worker %d finished populating...\n", n);
    //while (1) {
        // to the workers to analyse potential changes for the next round.
        for (int y = 0; y < IMHT; y++) {        // Go through all lines.
            for (int x = 0; x < (IMWD/2); x++) {  // Go through each pixel per line.
                int count = 0;
                for (int j = 0; j < 3; j++) {
                    for (int i = 0; i < 3; i++) {
                        if (i == 1 && j == 1) {
                            i++;
                        }
                        if (image[(x + i - 1 + (IMWD/2)) % (IMWD/2)][(y + j - 1 + IMHT) % IMHT] == 255) {
                            count++;
                        }
                    }
                }
                /* LOGIC FOR IF CELL WILL CHANGE:
                • any live cell with fewer than two live neighbours dies.
                • any live cell with two or three live neighbours is unaffected.
                • any live cell with more than three live neighbours dies.
                • any dead cell with exactly three live neighbours becomes alive.
                */
                uchar zero = 0;
                uchar twofivefive = 255;
                // If alive
                if (image[x][y] == 255) {
                    if (count < 2 || count > 3) {
                        //if (!n) printf("Wk%d - here1: (%d,%d)\n", n, x, y);
                        c_fromDist <: zero;  // Now dead.
                    }
                    else {
                        //if (!n) printf("Wk%d - here1a: (%d,%d)\n", n, x, y);
                        c_fromDist <: image[x][y];
                    }
                }
                // If dead
                else if (count == 3) {
                    //if (!n) printf("Wk%d - here2: (%d,%d)\n", n, x, y);
                    c_fromDist <: twofivefive;    // Now alive.
                }
                else {
                    //if (!n) printf("Wk%d - here2a: (%d,%d)\n", n, x, y);
                    c_fromDist <: image[x][y];
                }
            }
        }
    //}

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
    int tilted = 0;

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

    // Probe the orientation x-axis forever.
    while (1) {
        // Check until new orientation data is available.
        do {
            status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
        } while (!status_data & 0x08);

        // Get new x-axis tilt value.
        int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

        // Send signal to distributor after first tilt.
        if (!tilted) {
            if (x>30) {
                tilted = 1 - tilted;
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

    i2c_master_if i2c[1];             // interface to orientation
    //int n = 2;                        // The number of workers.

    char infname[] = "test.pgm";      // put your input image path here
    char outfname[] = "testout.pgm";  // put your output image path here
    chan c_inIO, c_outIO, c_control;  // extend your channel definitions here
    chan c_workers[2];                // worker channels (one for each worker).

    par {
        i2c_master(i2c, 1, p_scl, p_sda, 10);  // server thread providing orientation data.
        orientation(i2c[0],c_control);         // client thread reading orientation data.
        DataInStream(infname, c_inIO);         // thread to read in a PGM image.
        DataOutStream(outfname, c_outIO);      // thread to write out a PGM image.
        distributor(c_inIO, c_outIO, c_control, c_workers, 2);  // thread to coordinate work on image.
        worker(c_workers[0], 0);                  // thread to do work on an image.
        worker(c_workers[1], 1);                  // thread to do work on an image.
    }

  return 0;
}
