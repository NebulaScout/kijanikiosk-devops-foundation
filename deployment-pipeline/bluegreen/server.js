// server.js (minimal kk-api simulator for deployment testing)
// Create one of these per version by changing APP_VERSION

const http = require("http");
const APP_VERSION = process.env.APP_VERSION || "v1.4.0";
const PORT = parseInt(process.env.PORT || "3001", 10);

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        status: "ok",
        version: APP_VERSION,
        port: PORT,
        uptime: process.uptime(),
      }),
    );
    return;
  }
  res.writeHead(200);
  res.end(`KijaniKiosk API ${APP_VERSION} on port ${PORT}\n`);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`kk-api ${APP_VERSION} listening on port ${PORT}`);
});
