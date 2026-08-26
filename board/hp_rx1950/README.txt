rx1950-linux boot card

1. Copy this card image to an SD card.
2. Start haret.exe from Windows Mobile.
3. HaRET reads startup.txt, detects RX1950/S3C2442, relocates the image by
   0x1000000, passes machine type 952, and boots zImage. This leaves enough
   room below the compressed image for the current kernel to decompress.

The internal Windows Mobile installation is not changed.
