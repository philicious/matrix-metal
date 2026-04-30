## Matrix Screensaver for MacOS

This is based on the original Matrix screensaver from https://www.doublecreations.com/projects/matrixgl/

The older MacOS port by Stephan Sudre http://s.sudre.free.fr/Software/matrixgl.html still used OpenGL renderer and the older Screensaver Framework for MacOS. Causing it to run as a legacy-screensaver, consuming alot of memory.

This port uses MacOS Metal instead of OpenGL and was made with the help of ChatGPT Codex.

### Development

For working on the rendering, build as standalone windowed app:

> make standalone && make run

Controls available in standalone app:
   - `q` or `Esc`: quit
   - `s`: toggle classic mode
   - `p`: pause
   - `n`: next depth image

### Bundling as screensaver

For creating an installable screensaver, run

> make saver-bundle

### Installing

Copy the `MatrixMetal.saver` to `~/Library/Screen Savers` or run

> make install-saver

Note: Before re-installing, run make reset-screensaver to get rid of older cached versions

### Donate

If you like this screensaver, you can

<a href='https://ko-fi.com/C1C31YPQBW' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi5.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

I dont take credit for the original artwork but for porting the source to MacOS Metal framework, which took some hours, despite using AI.
