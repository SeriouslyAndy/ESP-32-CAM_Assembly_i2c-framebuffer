#include <WiFi.h>
#include <WebServer.h>

#include "esp_camera.h"
#include "img_converters.h"

// Project adapted in order to prove my emu8086 program
// Auth: JavaKet (Mitran Andrei)
const char* WIFI_SSID = "nambani";
const char* WIFI_PASS = "123andy123";
WebServer server(80);
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22
//computation outs
struct ComputeOut {
  uint32_t frame_bytes_lo;
  uint32_t frame_bytes_hi;
  uint16_t total_cycles;
  uint16_t high_cycles;
  uint16_t low_cycles;
};
extern "C" void emu8086_xtensa(
  uint32_t w,// a2
  uint32_t h,// a3
  uint32_t bpp,// a4
  uint32_t apb_khz,// a5
  uint32_t scl_khz,// a6
  ComputeOut* out// a7
);

// emu8086 proj rewritten for ESP32 cam
// It computes frame buffer bytes and I2C timing like in da 8086 program
static ComputeOut emu8086_xtansa(uint32_t w, uint32_t h, uint32_t bpp,
                                 uint32_t apb_khz, uint32_t scl_khz) {
  ComputeOut out{};
  emu8086_xtensa(w, h, bpp, apb_khz, scl_khz, &out);
  return out;
}
//web ui
static const char INDEX_HTML[] PROGMEM = R"HTML(
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Camera</title>
  <style>
    body{font-family:Arial;margin:16px}
    button{font-size:16px;padding:10px 14px}
    img{max-width:100%;height:auto;display:block;margin-top:12px;border:1px solid #ddd}
    .row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
    code{background:#f4f4f4;padding:2px 6px;border-radius:4px}
  </style>
</head>
<body>
  <h2>ESP32 Camera</h2>
  <div class="row">
    <button onclick="take()">Take picture</button>
    <span id="status">Idle</span>
  </div>
  <p>Endpoint: <code>/capture</code></p>
  <img id="img" alt="(no image yet)"/>

<script>
async function take(){
  const s = document.getElementById('status');
  s.textContent = 'Capturing...';
  try{
    // cache-bust with timestamp
    const url = '/capture?t=' + Date.now();
    const img = document.getElementById('img');
    img.src = url;
    img.onload = ()=> s.textContent = 'Done';
    img.onerror = ()=> s.textContent = 'Error loading image';
  }catch(e){
    s.textContent = 'Error';
  }
}
</script>
</body>
</html>
)HTML";
//cam init
static bool init_camera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0       = Y2_GPIO_NUM;
  config.pin_d1       = Y3_GPIO_NUM;
  config.pin_d2       = Y4_GPIO_NUM;
  config.pin_d3       = Y5_GPIO_NUM;
  config.pin_d4       = Y6_GPIO_NUM;
  config.pin_d5       = Y7_GPIO_NUM;
  config.pin_d6       = Y8_GPIO_NUM;
  config.pin_d7       = Y9_GPIO_NUM;
  config.pin_xclk     = XCLK_GPIO_NUM;
  config.pin_pclk     = PCLK_GPIO_NUM;
  config.pin_vsync    = VSYNC_GPIO_NUM;
  config.pin_href     = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn     = PWDN_GPIO_NUM;
  config.pin_reset    = RESET_GPIO_NUM;

  config.xclk_freq_hz = 20000000;
  config.fb_location  = CAMERA_FB_IN_PSRAM;
  config.grab_mode    = CAMERA_GRAB_WHEN_EMPTY;
// had issues cuz jpeg not supported so I changed it 
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size   = FRAMESIZE_VGA; //640x480
  config.jpeg_quality = 12; //the lower the better
  config.fb_count     = 2;

  esp_err_t err = esp_camera_init(&config);
  if (err == ESP_OK) {
    sensor_t *s = esp_camera_sensor_get();
    Serial.printf("Camera OK. PID=0x%04x\n", s->id.PID);
    return true;
  }
  Serial.printf("camera init JPEG failed: 0x%x\n", err);
  Serial.println("trying RGB565 fallback...");
//fallback: RGB565
  esp_camera_deinit();

  config.pixel_format = PIXFORMAT_RGB565;
  config.frame_size   = FRAMESIZE_QVGA; //320x240
  config.fb_count     = 1;

  err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init RGB565 failed: 0x%x\n", err);
    return false;
  }

  sensor_t *s = esp_camera_sensor_get();
  Serial.printf("Camera OK (RGB565). PID=0x%04x\n", s->id.PID);
  return true;
}
//http handlers
static void handle_root() {
  server.send_P(200, "text/html", INDEX_HTML);
}

static void handle_capture() {
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    server.send(500, "text/plain", "Camera capture failed");
    return;
  }
//return jpeg
  if (fb->format == PIXFORMAT_JPEG) {
    server.sendHeader("Content-Type", "image/jpeg");
    server.sendHeader("Content-Disposition", "inline; filename=capture.jpg");
    server.sendHeader("Cache-Control", "no-store");
    server.send_P(200, "image/jpeg", (const char*)fb->buf, fb->len);
    esp_camera_fb_return(fb);
    return;
  }
  //convert RGB565 to JPEG
  uint8_t *jpg_buf = nullptr;
  size_t jpg_len = 0;

  bool ok = fmt2jpg(fb->buf, fb->len, fb->width, fb->height, fb->format, 80, &jpg_buf, &jpg_len);
  esp_camera_fb_return(fb);

  if (!ok || !jpg_buf || jpg_len == 0) {
    server.send(500, "text/plain", "JPEG convert failed");
    return;
  }

  server.sendHeader("Content-Type", "image/jpeg");
  server.sendHeader("Content-Disposition", "inline; filename=capture.jpg");
  server.sendHeader("Cache-Control", "no-store");
  server.send_P(200, "image/jpeg", (const char*)jpg_buf, jpg_len);

  free(jpg_buf);
}

void setup() {
  Serial.begin(115200);
  Serial.println();
//just like in the emu8086 program we will have the same values here
  uint32_t WIDTH = 320;
  uint32_t HEIGHT = 240;
  uint32_t BPP = 2; //RGB565
  uint32_t APB_KHZ = 80000; //80MHz
  uint32_t SCL_KHZ = 400; //400 

  ComputeOut c = emu8086_xtansa(WIDTH, HEIGHT, BPP, APB_KHZ, SCL_KHZ);
  uint64_t frame_bytes = ((uint64_t)c.frame_bytes_hi << 32) | c.frame_bytes_lo;

  Serial.println("Computation Results");
  Serial.printf("Frame bytes = %llu\n", (unsigned long long)frame_bytes);
  Serial.printf("I2C: total_cycles = %u\n", c.total_cycles);
  Serial.printf("I2C: high_cycles  = %u\n", c.high_cycles);
  Serial.printf("I2C: low_cycles   = %u\n", c.low_cycles);
  Serial.println("O------------------w-------------------O");

  //init camera if
  if (!init_camera()) {
    Serial.println("Camera init failed (see log above).");
    while (true) delay(1000);
  }
// wifi connection
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(250);
    Serial.print("-");
  }
  Serial.println();
  Serial.print("open browser: http://");
  Serial.println(WiFi.localIP());
  server.on("/", HTTP_GET, handle_root);
  server.on("/capture", HTTP_GET, handle_capture);
  server.begin();
}

void loop() {
  server.handleClient();
}
