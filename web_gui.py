import glob
import json
import os

from flask import Flask, Response, jsonify, request

WIPE_DB = '/tmp/wipe_db'
CONFIG_FILE = os.path.join(WIPE_DB, 'config.json')
LOG_FILE = '/var/log/disktoolitl/disktoolitl.log'


def _get_disk_states():
    states = []
    for path in sorted(glob.glob(os.path.join(WIPE_DB, '*_state.json'))):
        try:
            with open(path, 'r') as f:
                states.append(json.load(f))
        except Exception:
            pass
    return states


def _get_log_lines(n=80):
    try:
        with open(LOG_FILE, 'r') as f:
            lines = f.readlines()
        return [line.rstrip() for line in lines[-n:]]
    except Exception:
        return []

_HTML = """<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DiskToolITL 1.0</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0f172a;color:#e2e8f0;font-family:'Courier New',monospace;padding:24px;min-height:100vh}
h1{color:#38bdf8;font-size:1.9rem;letter-spacing:3px;margin-bottom:4px}
.sub{color:#475569;font-size:.8rem;margin-bottom:28px;letter-spacing:1px}
.stats{display:flex;gap:14px;margin-bottom:24px;flex-wrap:wrap}
.stat{background:#1e293b;border:1px solid #334155;border-radius:8px;padding:16px 28px;text-align:center;min-width:110px}
.stat-num{font-size:2.1rem;font-weight:bold;color:#38bdf8}
.stat-label{font-size:.7rem;color:#64748b;text-transform:uppercase;letter-spacing:1px;margin-top:2px}
.card{background:#1e293b;border:1px solid #334155;border-radius:8px;padding:22px;margin-bottom:20px}
.card-title{color:#94a3b8;font-size:.75rem;text-transform:uppercase;letter-spacing:2px;margin-bottom:16px}
table{width:100%;border-collapse:collapse}
th{text-align:left;color:#64748b;font-size:.7rem;text-transform:uppercase;letter-spacing:.5px;padding:8px 14px;border-bottom:1px solid #334155}
td{padding:12px 14px;border-bottom:1px solid #0f172a;font-size:.85rem;vertical-align:middle}
tr:last-child td{border-bottom:none}
tr:hover td{background:#243044}
.badge{display:inline-block;padding:3px 11px;border-radius:9999px;font-size:.7rem;font-weight:bold;letter-spacing:.5px}
.b-smart{background:#1e3a5f;color:#93c5fd}
.b-wiping{background:#78350f;color:#fde68a}
.b-done{background:#064e3b;color:#6ee7b7}
.b-error{background:#7f1d1d;color:#fca5a5}
.b-unknown{background:#1f2937;color:#9ca3af}
.bar-wrap{background:#0f172a;border-radius:4px;height:6px;margin-top:6px;overflow:hidden;width:160px}
.bar-fill{height:100%;border-radius:4px;transition:width .6s ease}
.bar-wiping{background:#f59e0b}
.bar-done{background:#10b981}
.pct{color:#f59e0b;font-size:.75rem;margin-left:8px}
.pct-done{color:#10b981}
.smart-pass{color:#10b981}
.smart-fail{color:#ef4444}
.smart-unk{color:#64748b}
.log-box{background:#0a0f1a;border:1px solid #1e293b;border-radius:6px;padding:14px;height:320px;overflow-y:auto;font-size:.78rem;color:#94a3b8;line-height:1.6}
.log-line{border-bottom:1px solid #111827;padding:1px 0}
.empty{color:#475569;text-align:center;padding:40px;font-size:.9rem}
.settings-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
input[type=text]{flex:1;min-width:260px;background:#0f172a;border:1px solid #334155;border-radius:6px;padding:9px 14px;color:#e2e8f0;font-size:.85rem;outline:none}
input[type=text]:focus{border-color:#38bdf8}
button{background:#0369a1;color:#fff;border:none;padding:9px 22px;border-radius:6px;cursor:pointer;font-size:.85rem;font-weight:bold;letter-spacing:.5px}
button:hover{background:#0284c7}
.ok{color:#10b981;font-size:.8rem;display:none;margin-left:6px}
</style>
</head>
<body>
<h1>DiskToolITL</h1>
<p class="sub">Automatisches Disk-Wipe-System &mdash; v1.0</p>

<div class="stats">
  <div class="stat"><div class="stat-num" id="s-total">0</div><div class="stat-label">Gesamt</div></div>
  <div class="stat"><div class="stat-num" id="s-wiping">0</div><div class="stat-label">Aktiv</div></div>
  <div class="stat"><div class="stat-num" id="s-done">0</div><div class="stat-label">Fertig</div></div>
  <div class="stat"><div class="stat-num" id="s-error">0</div><div class="stat-label">Fehler</div></div>
</div>

<div class="card">
  <div class="card-title">Datentr&auml;ger</div>
  <div id="disk-wrap"></div>
</div>

<div class="card">
  <div class="card-title">Live-Log</div>
  <div class="log-box" id="log-box"></div>
</div>

<div class="card">
  <div class="card-title">Einstellungen &mdash; Server-URL</div>
  <div class="settings-row">
    <input type="text" id="url-input" placeholder="http://192.168.1.100:5000/api/smart">
    <button onclick="saveConfig()">Speichern</button>
    <span class="ok" id="ok-msg">&#10003; Gespeichert</span>
  </div>
</div>

<script>
function badgeClass(s){
  return s==='SMART'?'b-smart':s==='WIPING'?'b-wiping':s==='DONE'?'b-done':s==='ERROR'?'b-error':'b-unknown';
}

function renderDisks(disks){
  if(!disks.length) return '<div class="empty">Keine Datentr&auml;ger erkannt &mdash; warte auf Verbindung&hellip;</div>';
  const rows = disks.map(d=>{
    const pct = d.progress||0;
    let smartHtml='<span class="smart-unk">&mdash;</span>';
    if(d.smart_passed===true) smartHtml='<span class="smart-pass">&#10003; PASSED</span>';
    else if(d.smart_passed===false) smartHtml='<span class="smart-fail">&#10007; FAILED</span>';
    let barHtml='';
    if(d.status==='WIPING'){
      barHtml=`<span class="pct">${pct.toFixed(1)}%</span><div class="bar-wrap"><div class="bar-fill bar-wiping" style="width:${pct}%"></div></div>`;
    } else if(d.status==='DONE'){
      barHtml=`<span class="pct pct-done">100%</span><div class="bar-wrap"><div class="bar-fill bar-done" style="width:100%"></div></div>`;
    }
    return `<tr>
      <td>${d.device}</td>
      <td>${d.type}</td>
      <td>${d.model||'&mdash;'}</td>
      <td>${d.serial||'&mdash;'}</td>
      <td>${d.size_gb?d.size_gb+' GB':'&mdash;'}</td>
      <td>${smartHtml}</td>
      <td><span class="badge ${badgeClass(d.status)}">${d.status}</span>${barHtml}</td>
    </tr>`;
  }).join('');
  return `<table>
    <thead><tr>
      <th>Device</th><th>Typ</th><th>Modell</th><th>Seriennummer</th><th>Gr&ouml;&szlig;e</th><th>SMART</th><th>Status</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

function updateStats(disks){
  document.getElementById('s-total').textContent=disks.length;
  document.getElementById('s-wiping').textContent=disks.filter(d=>d.status==='WIPING').length;
  document.getElementById('s-done').textContent=disks.filter(d=>d.status==='DONE').length;
  document.getElementById('s-error').textContent=disks.filter(d=>d.status==='ERROR').length;
}

function updateLog(logs){
  const box=document.getElementById('log-box');
  const atBottom=box.scrollHeight-box.clientHeight<=box.scrollTop+8;
  box.innerHTML=logs.map(l=>`<div class="log-line">${l}</div>`).join('');
  if(atBottom) box.scrollTop=box.scrollHeight;
}

function poll(){
  fetch('/api/status').then(r=>r.json()).then(d=>{
    document.getElementById('disk-wrap').innerHTML=renderDisks(d.disks);
    updateStats(d.disks);
    updateLog(d.logs);
  }).catch(()=>{});
}

function loadConfig(){
  fetch('/api/config').then(r=>r.json()).then(d=>{
    document.getElementById('url-input').value=d.server_url||'';
  }).catch(()=>{});
}

function saveConfig(){
  const url=document.getElementById('url-input').value.trim();
  fetch('/api/config',{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({server_url:url})
  }).then(()=>{
    const m=document.getElementById('ok-msg');
    m.style.display='inline';
    setTimeout(()=>{m.style.display='none';},3000);
  }).catch(()=>{});
}

loadConfig();
poll();
setInterval(poll,2000);
</script>
</body>
</html>"""


def create_app():
    app = Flask(__name__)

    @app.route('/')
    def index():
        return Response(_HTML, mimetype='text/html')

    @app.route('/api/status')
    def api_status():
        disks = _get_disk_states()
        logs  = _get_log_lines(80)
        return jsonify({'disks': disks, 'logs': logs})

    @app.route('/api/config', methods=['GET', 'POST'])
    def api_config():
        os.makedirs(WIPE_DB, exist_ok=True)
        if request.method == 'POST':
            data = request.get_json(force=True) or {}
            url = data.get('server_url', '')
            with open(CONFIG_FILE, 'w') as f:
                json.dump({'server_url': url}, f)
            return jsonify({'ok': True})
        try:
            with open(CONFIG_FILE, 'r') as f:
                return jsonify(json.load(f))
        except Exception:
            return jsonify({'server_url': ''})

    return app
