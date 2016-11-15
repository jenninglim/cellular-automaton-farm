# Cellular-automaton-farm
## Ideas

* Use 2 bits of the 32 bits to store the edge cases.  
Distributors keeps track of this. (When the size of the image is not divisible by 32)

## Todo

1. Think of a way for distributors to continuously work. (Maybe abstract away some details). 
 
  Remember to maintain the rep invariant, by using assign edges function.

## Extension
* Compress uint32 by reducing 0s. (Requires thorough formalisations).
 
 Distributor must keep track of the index in the int and the length of the compressed bits
 
## Done
* Bit implementation for a single round.
* The first and last bit is used for "edge cases". If the 30 bits are unused then the next unused bit will also store the left edge case.

 Defintion: Edge cases are additional information required to process each point of the game of life farm, so that the next state can be found.
 
 This representation invariant MUST BE MAINTAINED.
 
 
