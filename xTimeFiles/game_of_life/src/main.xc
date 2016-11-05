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

// A 3x3 matrix.
typedef struct matrix3 {
    uchar s_image[3][3];
    uchar colour;  // Colour of the centre cell.
} matrix3;

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
        for (int x = 0; x < IMWD; x++) {
            c_out <: line[x];
            printf( "-%4.1d ", line[ x ] ); // Show image values.
        }
        printf("\n");
    }

    // Close PGM image file.
    _closeinpgm();
    printf( "DataInStream: Done...\n" );
    return 0;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Distributor that farms out parts of the image to worker threads who the Game of Life!
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend c_toWorker[n], unsigned n) {
    uchar image[IMWD][IMHT];  // The full image at the start of a round.

    // Start up and wait for tilting of the xCore-200 Explorer.
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for Board Tilt...\n" );
    fromAcc :> int value;

    // Construct the image pixel by pixel.
    printf( "Populating image array...\n" );
    for (int y = 0; y < IMHT; y++) {       // Go through all lines.
        for( int x = 0; x < IMWD; x++ ) {  // Go through each pixel per line.
            c_in :> image[x][y];           // Read the pixel value.
        }
    }

    // Create a 3x3 matrix for each pixel (and its surrounding cells) and farm out
    // to the workers to analyse potential changes for the next round.
    printf( "Processing...\n" );
    for(int y = 0; y < IMHT; y++) {        // Go through all lines.
        for( int x = 0; x < IMWD; x++ ) {  // Go through each pixel per line.
            matrix3 currentM;              // Create a 3x3 matrix.
            for (int i = 0; i < 4; i++) {
                for (int j = 0; j < 4; j++) {
                    currentM.s_image[i][j] = image[(x + i - 1 + IMWD) % IMWD][(y + j - 1 + IMHT) % IMHT];
                }
            }
            c_toWorker[0] <: currentM;     // Send to a worker to process.
            c_toWorker[0] :> currentM;     // Receive back the processed matrix.
            c_out <: currentM.colour;      // Print and save the pixel.
        }
    }

    printf( "\nOne processing round completed...\n" );
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Worker that processes part of the image.
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker(chanend c_fromDist) {
    matrix3 currentM;
    c_fromDist :> currentM;
    int count = 0;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            if (j == 1) j++;
            if (currentM.s_image[i][j] == 255) count++;
        }
        if (i == 1) i++;
    }

    /* LOGIC FOR IF CELL WILL CHANGE:
    • any live cell with fewer than two live neighbours dies.
    • any live cell with two or three live neighbours is unaffected.
    • any live cell with more than three live neighbours dies.
    • any dead cell with exactly three live neighbours becomes alive.
    */
    // If alive
    if (currentM.s_image[1][1] == 255) {
        if (count < 2 || count > 3) {
            currentM.colour = 0;  // Now dead.
        }
    }
    // If dead
    else if (count == 3) {
        currentM.colour = 255;    // Now alive.
    }

    c_fromDist <: currentM;
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
    printf( "DataOutStream: Start...\n" );
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
        printf( "DataOutStream: Line written...\n" );
    }

    // Close the PGM image.
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

    char infname[] = "test.pgm";      // put your input image path here
    char outfname[] = "testout.pgm";  // put your output image path here
    chan c_inIO, c_outIO, c_control;  // extend your channel definitions here
    chan c_workers[1];                // worker channels (one for each worker).

    par {
        i2c_master(i2c, 1, p_scl, p_sda, 10);  // server thread providing orientation data.
        orientation(i2c[0],c_control);         // client thread reading orientation data.
        DataInStream(infname, c_inIO);         // thread to read in a PGM image.
        DataOutStream(outfname, c_outIO);      // thread to write out a PGM image.
        distributor(c_inIO, c_outIO, c_control, c_workers, 1);  // thread to coordinate work on image.
        worker(c_workers[0]);                  // thread to do work on an image.
    }

  return 0;
}
