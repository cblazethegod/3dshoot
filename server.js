const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;
const clients = new Map(); // ws -> {id,name,team,x,y,z,yaw,pitch,health,lastSeen}
const players = {}; // id -> state

function broadcast(obj){
  const data = JSON.stringify(obj);
  for (const ws of clients.keys()){
    if (ws.readyState === WebSocket.OPEN) ws.send(data);
  }
}

const server = http.createServer();
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
  clients.set(ws, null);
  ws.on('message', (raw) => {
    try {
      const m = JSON.parse(raw);
      if (m.t === 'join') {
        clients.set(ws, { id: m.id, name: m.name || 'Player', team: m.team || 'red', x: 0, y: 2, z: 0, yaw: 0, pitch: 0, health: 100, lastSeen: Date.now() });
        players[m.id] = clients.get(ws);
        ws.send(JSON.stringify({ t: 'joined', id: m.id }));
        broadcast({ t: 'state', players });
      } else if (m.t === 'state' && clients.has(ws)) {
        const c = clients.get(ws) || {};
        Object.assign(c, { x: m.x, y: m.y, z: m.z, yaw: m.yaw, pitch: m.pitch, health: m.health, team: c.team || 'red', name: c.name || 'Player', lastSeen: Date.now() });
        clients.set(ws, c);
        players[c.id] = c;
        broadcast({ t: 'state', players });
      }
    } catch (e) {}
  });
  ws.on('close', () => {
    const c = clients.get(ws);
    if (c) { delete players[c.id]; broadcast({ t: 'state', players }); }
    clients.delete(ws);
  });
});

setInterval(() => {
  const now = Date.now();
  for (const [ws, c] of clients.entries()) {
    if (c && now - c.lastSeen > 5000) {
      delete players[c.id];
      clients.delete(ws);
      ws.close();
    }
  }
  broadcast({ t: 'state', players });
}, 1000 / 20);

server.listen(PORT, () => console.log(`Multiplayer server on ws://localhost:${PORT}`));
