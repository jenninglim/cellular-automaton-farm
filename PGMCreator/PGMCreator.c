// Build with: gcc -std=c99 -O3 PGMCreator.c pgmIO.c -o PGMCreator
// Run with:   ./PGMCreator

#include "pgmIO.h"

typedef unsigned char uchar;  // Using uchar as shorthand.

#define IMWD 1024
#define IMHT 30
#define POINTS 44
#define X 255

void createPGMFile(uchar image[IMHT][IMWD]) {
    int res;
    uchar line[IMWD];
    char outfname[] = "imageout.pgm";  // Output image path

    // Open PGM file.
    res = _openoutpgm(outfname, IMWD, IMHT);
    if (res) {
        printf("DataOutStream: Error opening %s\n.", outfname);
        return;
    }

    //Compile each line of the image and write the image line-by-line.
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD; x++) {
            line[x] = image[y][x];
        }
        _writeoutline(line, IMWD);
    }

    // Close the PGM image.
    _closeoutpgm();
    printf("\nDataOutStream: Done...\n");
}

void generateImage(uchar image[IMHT][IMWD]) {

    /* LIGHWEIGHT SPACESHIP (8x8).
    uchar tempImage[IMHT][IMWD] = {{0,0,0,0,0,0,0,0},
                                   {0,0,0,0,0,0,0,0},
                                   {0,0,0,0,0,0,0,0},
                                   {0,0,X,X,X,X,0,0},
                                   {0,X,0,0,0,X,0,0},
                                   {0,0,0,0,0,X,0,0},
                                   {0,X,0,0,X,0,0,0},
                                   {0,0,0,0,0,0,0,0}};
    */
    //alive points
    uchar points[POINTS][2] = {{4,2}, //1
                               {8,2}, //2
                               {9,2}, //3
                               {21,2}, //4
                               {22,2}, //5
                               {26,2}, //6
                               {5,3}, //7
                               {8,3}, //8
                               {9,3}, //9
                               {21,3}, //10
                               {22,3}, //11
                               {25,3}, //12
                               {5,4}, //13
                               {8,4}, //14
                               {22,4}, //15
                               {5,5}, //16
                               {25,5}, //17
                               {5,6}, //18
                               {10,6}, //19
                               {11,6}, //20
                               {13,6}, //21
                               {17,6}, //22
                               {19,6}, //23
                               {20,6}, //24
                               {25,6}, //25
                               {2, 7}, //26
                               {5, 7}, //27
                               {11, 7}, //28
                               {12,7}, //29
                               {13,7}, //30
                               {17,7}, //31
                               {18,7}, //32
                               {19,7},
                               {25,7}, //34
                               {28,7}, //35
                               {3,8},
                               {4,8},//37
                               {5,8},
                               {12,8},
                               {18,8}, //40
                               {25,8},
                               {26,8},
                               {27,8},
                               {25,4} //44
    };
    int count = 0;
    uchar tempImage[IMHT][IMWD];
    for (int i = 0; i < IMHT; i ++) {
        for (int j = 0; j < IMWD; j ++) {
            tempImage[i][j] = 0;
            for (int k = 0; k < POINTS; k ++) {
                if (points[k][0] == i % 32 && points[k][1] == j ) {
                    tempImage[i][j] = X;
                }
            }
        }
        
    }

    memcpy(image, tempImage, sizeof(uchar) * IMHT * IMWD);
}

int main(int n, char *args[n]) {

    uchar image[IMHT][IMWD];
    generateImage(image);
    createPGMFile(image);

    return 0;
}
