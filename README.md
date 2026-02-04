# Project Documentation 
Auth: Mitran Andrei 
Group: 1231EA 
## Topic: Working I2C Frame transfer driver for esp 32 cam in assembly. 

Project is divided into two parts: 
• emu8086 part: computes frame buffer size + I2C timing and PRINTS it. It also SIMULATES 
communication with Arduino by building a serial line in RAM and printing it. 
• Arduino part: hosts a local web page that works as a control panel. It captures a frame and 
returns it as JPEG. At boot it also calls Xtensa assembly to compute the same frame/I2C 
math and prints it to Serial. 

## Architecture  
• Browser -> ESP32 HTTP server: GET / (UI), GET /capture (image). 
• ESP32 camera driver: esp_camera_fb_get() grabs a frame buffer. 
• If sensor supports JPEG: send JPEG directly; otherwise capture RGB565 and convert to 
JPEG with fmt2jpg(). 
• Computation: Xtensa assembly function emu8086_xtensa() computes the same values as 
the emu8086 program. 

## Formulas used 
A) Frame buffer size (bytes) 
frame_bytes = WIDTH * HEIGHT * BPP 
WIDTH, HEIGHT are pixels 
BPP is bytes per pixel (RGB565 = 2, grayscale = 1, etc.) 
In 8086 we store the result as 32bit (FRAME_HI:FRAME_LO). In ESP32 we use a 64-bit 
intermediate and keep lo/hi words. 
B) I2C timing 
total_cycles = APB_KHZ / SCL_KHZ 
high_cycles  = total_cycles / 2 
low_cycles   = total_cycles - high_cycles 
remainder    = APB_KHZ % SCL_KHZ  (only for debug / accuracy checks) 
Interpretation: this is a simplified way to estimate how many APB clock cycles fit in one I2C clock 
period.  

## emu8086 simulation 
Emu program runs in a PC/DOS emulator, so it cannot really talk to an ESP32 over COM1 (for 
me it was COM14) in a reliable way.
o Instead of writing the whole program in assembly (Instead of the intended driver only, of 
course), I choose to simulate the steps in 8086 and translate this driver in xtensa 
assembly for arduino process. 
• Build the line: FB=<u32>,T=<u16>,H=<u16>,L=<u16>
into COMBUF. 
• Print: “Sending to COM1 as: <line>” 
• This avoids BIOS INT 14h issues like “interrupt not defined yet”. 

## Hardware side
Arduino sketch is responsible for: 
• Connecting to WiFi and prints local IP. 
• Serves web page in order to control the camera 
• Button loads /capture (cache-busted) into an <img> tag. 
• Server handler captures a frame and returns image/jpeg. 

## Xtensa assembly bridge 
The Arduino code calls an external Xtensa assembly function: 
extern "C" void emu8086_xtensa(uint32_t w, uint32_t h, uint32_t bpp, 
uint32_t apb_khz, uint32_t scl_khz, ComputeOut* out); 
This function computes: 
• frame_bytes (low 32 bits stored in out->frame_bytes_lo) 
• total_cycles, high_cycles, low_cycles 

Note: I used “mull” for the low 32-bit product, and __udivsi3 for division (portable even if 
hardware divide is not enabled). 

## Common issues + fixes 
• “JPEG format is not supported on this sensor”: start camera in RGB565 and convert to JPEG 
in /capture. 
• Xtensa: “unknown opcode mul”: use mull/muluh (or only mull if you only keep low 32). 
• Xtensa: “unaligned entry instruction”: keep .align 4 before the function label. 
• If /capture is slow: use smaller frame size (QVGA) or lower JPEG quality number for better 
quality / higher CPU cost trade-off. 
Issues only: Overflow (program cant go for something like 800Mhz. As well as arduino doesn’t 
support my assembly code without xtensa.

``Example output``

``Computation Results ``

``Output nr = 1 ``

``Frame bytes = 153600 ``

``I2C: total_cycles = 200`` 

``I2C: high_cycles  = 100 ``

``I2C: low_cycles   = 100 ``

``Sending to COM1 as: FB=153600,T=200,H=100,L=100 ``

``Press R to recompute, ESC to quit...`` 

Sources: 
https://medium.com/@bayotosho/xtensa-lx7-assembly-walkthrough-by-example-c43f529bdeb1 
https://www.instructables.com/How-to-Use-the-ESP32-CAM-for-Beginners/ 
https://randomnerdtutorials.com/esp32-cam-video-streaming-face-recognition-arduino-ide/ 
https://docs.platformio.org/en/latest/boards/espressif32/esp32cam.html 
https://documentation.espressif.com/esp32_technical_reference_manual_en.pdf 
https://medium.com/@aleksej.gudkov/8086-assembly-code-examples-a-beginners-guide-3aeafd3fa808 
https://yassinebridi.github.io/asm-docs/asm_tutorial_01.html 

https://godbolt.org

