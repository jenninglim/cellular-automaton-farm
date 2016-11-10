# Cellular-automaton-farm
**TODO**

1. Query warnings.
2. Do pointers work the same in XC?
3. Make uchar implementation work with Geometric Parallelism.
4. Make uchar implementation work with Farming.

Extension

1. Split the bytes into bits.
2. extend to include arbitrary size images (i.e. not just dimensions that are powers of 2).
3. implement function that returns an element in x and y position in a 32 bit character array.
4. Identify the sparse parts of the map and disregard using bit manipulation (after we have finished bytes to bits).

  Using bit manipulation and OR operations we can find "dead" areas of the map.
  Potentially, start disregarding multiple dead zones on the same row (the distributor must keep track the location that is sent to the worker).

