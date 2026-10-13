const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname,'dist');
const prefix = '/services/crawl4ai';
const types = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'application/javascript; charset=utf-8','.svg':'image/svg+xml'};
http.createServer((req,res) => {
  const url = new URL(req.url,'http://localhost');
  if (url.pathname === '/' || url.pathname === prefix) {res.writeHead(308,{Location:prefix+'/'});res.end();return;}
  if (url.pathname.startsWith(prefix+'/api/')) {
    const upstream = http.request({hostname:'127.0.0.1',port:11235,path:url.pathname.slice((prefix+'/api').length)+url.search,method:req.method,headers:req.headers},reply => {res.writeHead(reply.statusCode,reply.headers);reply.pipe(res);});
    upstream.on('error',()=>{res.writeHead(503,{'Content-Type':'application/json'});res.end('{"detail":"Preview API unavailable"}');});req.pipe(upstream);return;
  }
  if (!url.pathname.startsWith(prefix+'/')) {res.writeHead(404);res.end();return;}
  let name;
  try {name = path.resolve(root,'.'+decodeURIComponent(url.pathname.slice(prefix.length)));} catch {res.writeHead(400);res.end();return;}
  if (name !== root && !name.startsWith(root+path.sep)) {res.writeHead(403);res.end();return;}
  try {
    if (fs.statSync(name).isDirectory()) name=path.join(name,'index.html');
    if (!fs.statSync(name).isFile()) throw new Error();
  } catch {res.writeHead(404);res.end('Not found');return;}
  res.writeHead(200,{'Content-Type':types[path.extname(name)] || 'application/octet-stream'});fs.createReadStream(name).pipe(res);
}).listen(Number(process.env.PORT || 5180),'127.0.0.1',()=>console.log('Service preview on http://127.0.0.1:'+(process.env.PORT || 5180)+prefix+'/'));
