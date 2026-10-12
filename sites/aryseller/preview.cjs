const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, 'dist');
const types = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'application/javascript; charset=utf-8','.svg':'image/svg+xml','.xml':'application/xml','.txt':'text/plain; charset=utf-8'};
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname.startsWith('/services/crawl4ai/api/')) {
    const upstream = http.request({hostname:'127.0.0.1',port:11235,path:url.pathname.slice('/services/crawl4ai/api'.length)+url.search,method:req.method,headers:req.headers}, reply => {res.writeHead(reply.statusCode, reply.headers); reply.pipe(res);});
    upstream.on('error', () => {res.writeHead(503, {'Content-Type':'application/json'});res.end('{"detail":"Preview API unavailable"}');});req.pipe(upstream);return;
  }
  let name;
  try {name = path.resolve(root, '.' + decodeURIComponent(url.pathname));} catch {res.writeHead(400);res.end();return;}
  if (name !== root && !name.startsWith(root + path.sep)) {res.writeHead(403);res.end();return;}
  if (fs.existsSync(name) && fs.statSync(name).isDirectory()) name = path.join(name, 'index.html');
  if (!fs.existsSync(name) || !fs.statSync(name).isFile()) {res.writeHead(404);res.end('Not found');return;}
  res.writeHead(200, {'Content-Type':types[path.extname(name)] || 'application/octet-stream'});fs.createReadStream(name).pipe(res);
}).listen(5179, '127.0.0.1', () => console.log('Local: http://127.0.0.1:5179/'));
