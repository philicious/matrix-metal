## Matrix Screensaver for MacOS

This is based on the original Matrix screensaver from https://www.doublecreations.com/projects/matrixgl/

The older MacOS port by Stephan Sudre http://s.sudre.free.fr/Software/matrixgl.html still used OpenGL renderer and the older Screensaver Framework for MacOS. Causing it to run as a legacy-screensaver, consuming alot of memory.

This port was made with the help of ChatGPT Codex.

Build:
   $ cd macos
   $ make

Run:
   $ ./matrixgl-metal

Controls:
   - `q` or `Esc`: quit
   - `s`: toggle classic mode
   - `p`: pause
   - `n`: next depth image
