// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define IMHT 16   // Image height.
#define IMWD 16   // Image width.

#define ROUNDS 10  // Numbers of rounds to be processed.
#define WORKERS 2  // Number of workers processing the image.

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

in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
// on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

//DISPLAYS an LED pattern
int showLEDs(out port p, chanend fromVisualiser) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  while (1) {
    fromVisualiser :> pattern;   //receive new pattern from visualiser
    p <: pattern;                //send pattern to LED port
  }
  return 0;
}

//READ BUTTONS and send button pattern to userAnt
void buttonListener(in port b, chanend toUserAnt) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if ((r==13) || (r==14))     // if either button is pressed
    toUserAnt <: r;             // send button pattern to userAnt
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
    uchar image[IMWD][IMHT];  // The whole image being processed.
    uchar pixel;              // A single pixel being sent to a worker.

    // Start up and wait for tilting of the xCore-200 Explorer.
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for Board Tilt...\n" );
    fromAcc :> int value;

    // Read in the image from DataInStream.
    printf( "Populating image array...\n" );
    printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n[ 0]");
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD; x++ ) {
            c_in :> image[x][y];
        }
    }

    // Processing the rounds.
    printf("\nProcessing...\n");
    for (int r = 0; r < ROUNDS; r++) {
        // Send the image pixel by pixel to the workers.
        for (int y = 0; y < IMHT; y++) {
            for( int x = 0; x < IMWD; x++ ) {
                pixel = image[x][y];
                // On the boundaries between worker segments, send to both workers.
                if (x == 0 ||
                    x == ((IMWD / 2) -1) ||
                    x == (IMWD / 2) ||
                    x == IMWD - 1) {
                        c_toWorker[0] <: pixel;
                        c_toWorker[1] <: pixel;
                }
                // else send the first half to worker 0
                else if (x < (IMWD / 2)) {
                    c_toWorker[0] <: pixel;
                }
                // and the second half to worker 1.
                else {
                    c_toWorker[1] <: pixel;
                }
            }
        }
        //printf("\n");

        // Create a new image with the updated values.
        //uchar newImage[IMWD][IMHT];  // The new image.
        int x0 = 0;
        int y0 = 0;
        int x1 = IMWD/2;
        int y1 = 0;
        while (y0 < IMHT || y1 < IMHT) {
            select {
                case c_toWorker[0] :> pixel:
                    //printf("from 0: (%d,%d) = %d\n", x0, y0, pixel);
                    image[x0][y0] = pixel;
                    x0++;
                    if (x0 == IMWD/2) {
                        x0 = 0;
                        y0++;
                    }
                    break;
                case c_toWorker[1] :> pixel:
                    //printf("from 1: (%d,%d) = %d\n", x1, y1, pixel);
                    image[x1][y1] = pixel;
                    x1++;
                    if (x1 == IMWD) {
                        x1 = IMWD/2;
                        y1++;
                    }
                    break;
            }
        }
        //printf("x0:%d, y0:%d, x1:%d, y1:%d\n", x0, y0, x1, y1);
        printf( "Processing round %d complete...\n", r+1);
    }

    // Print and save the pixel.
    printf("\nSaving the new image...\n");
    printf("       [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]  [14]  [15]\n");
    for (int y = 0; y < IMHT; y++) {
        printf("[%2.1d]", y);
        for (int x = 0; x < IMWD; x++) {
            c_out <: image[x][y];
            printf( "-%4.1d ", image[x][y]);
        }
        printf("\n");
    }

    //printf( "One processing round completed...\n" );
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Worker that processes part of the image.
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker(chanend c_fromDist, int n) {
    uchar image[IMWD/2 + 2][IMHT];

    while (1) {
        // Reading in the worker's part of the image.
        if (n == 0) {  // Worker 0.
            for (int y = 0; y < IMHT; y++) {
                for( int x = 0; x < (IMWD/2 + 2); x++ ) {
                    if (x == IMWD/2 + 1) {  // gets the last column (of the whole image) last; puts it in column 0.
                        c_fromDist :> image[0][y];
                    }
                    else {
                        c_fromDist :> image[x+1][y];
                    }
                }
            }
        }
        else {  // Worker 1.
            for (int y = 0; y < IMHT; y++) {
                for( int x = 0; x < (IMWD/2 + 2); x++ ) {  // Start from column 1 as 0 is an overlap.
                    if (x == 0) {  // get the first column (of the whole image) first; puts it at the end.
                        c_fromDist :> image[IMWD/2 + 1][y];
                    }
                    else {
                        c_fromDist :> image[x-1][y];
                    }
                }
            }

        }
        //printf("Worker %d finished populating...\n", n);

        // Workers analyse potential changes for the next round.
        for (int y = 0; y < IMHT; y++) {
            for (int x = 1; x < (IMWD/2 + 1); x++) {  // Start from column 1 as 0 is an overlap.
                int count = 0;
                for (int j = 0; j < 3; j++) {
                    for (int i = 0; i < 3; i++) {
                        if (i == 1 && j == 1) {
                            i++;
                        }
                        if (image[(x + i - 1 + (IMWD/2+2)) % (IMWD/2+2)][(y + j - 1 + IMHT) % IMHT] == 255) {
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
                        c_fromDist <: zero;  // Now dead.
                    }
                    else {
                        c_fromDist <: image[x][y];
                    }
                }
                // If dead
                else if (count == 3) {
                    c_fromDist <: twofivefive;  // Now alive.
                }
                // No change.
                else {
                    c_fromDist <: image[x][y];
                }
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

    i2c_master_if i2c[1];              // interface to orientation

    char infname[] = "test.pgm";      // put your input image path here
    char outfname[] = "testout.pgm";  // put your output image path here
    chan c_inIO, c_outIO, c_control;   // extend your channel definitions here
    chan c_workers[WORKERS];                 // worker channels (one for each worker).

    par {
        i2c_master(i2c, 1, p_scl, p_sda, 10);  // server thread providing orientation data.
        orientation(i2c[0],c_control);         // client thread reading orientation data.
        DataInStream(infname, c_inIO);         // thread to read in a PGM image.
        DataOutStream(outfname, c_outIO);      // thread to write out a PGM image.
        distributor(c_inIO, c_outIO, c_control, c_workers, WORKERS);  // thread to coordinate work on image.
        worker(c_workers[0], 0);               // thread to do work on an image.
        worker(c_workers[1], 1);               // thread to do work on an image.
        
        //buttonListener(buttons, buttonsToUserAnt);
        // showLEDs(leds,visualiserToLEDs);
    }

  return 0;
}
