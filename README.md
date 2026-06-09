# MagicMouseWTouchpad
Adds touchpad feautures to Magic Mouse.

Uses the touch senstive top of the mouse to read input which moves the cursor and adds tap to click.

Edit the config.txt file to adjust sensitivity and smoothness. Must close and reopen app for adjustments to take effect.

update as of 6/9/26

Added gTouchHistory[2048][2] to store recent normalized touch inputs.
Appended each touch sample into the history buffer.
Added computeMovementFromHistory() to compute movement using a simple linear algebra transform:
averages recent delta vectors
applies a 2x2 sensitivity matrix
converts normalized movement into pixel movement
Updated the touch callback

now reads movement from the 2D touch history
derives deltaX / deltaY from the transformed history vector instead of just last-point difference
