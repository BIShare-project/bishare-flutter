/// A file the built-in Web-Share browser UI can list + download (offered files
/// or files this device has received).
class BrowserFile {
  const BrowserFile({
    required this.fileName,
    required this.fileType,
    required this.path,
    required this.size,
  });

  final String fileName;
  final String fileType;
  final String path;
  final int size;
}

/// The self-contained Web-Share page served at `GET /`. No external assets
/// (inline CSS + JS), dark-mode aware, optional PIN gate. Lets any browser on
/// the LAN download this device's files and upload files to it — no app needed.
String browserPageHtml({required String alias, required bool pinEnabled}) {
  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>BIShare — $alias</title>
<style>
  :root{--bg:#f5f5f7;--card:#fff;--fg:#1c1c1e;--muted:#8a8a8e;--border:#e3e3e8;--accent:#0a84ff;--radius:16px}
  @media(prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--fg:#f5f5f7;--muted:#98989f;--border:#2c2c2e;--accent:#0a84ff}}
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  body{margin:0;font:16px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--fg);padding:24px 16px 60px}
  .wrap{max-width:640px;margin:0 auto}
  h1{font-size:26px;margin:0 0 2px;letter-spacing:-.5px}
  .sub{color:var(--muted);margin:0 0 22px}
  .card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:16px;margin-bottom:16px}
  .row{display:flex;align-items:center;gap:12px;padding:12px 4px;border-bottom:1px solid var(--border)}
  .row:last-child{border-bottom:none}
  .row .meta{flex:1;min-width:0}
  .row .name{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .row .size{color:var(--muted);font-size:13px}
  a.btn,button{font:inherit;font-weight:600;border:none;border-radius:12px;padding:10px 16px;background:var(--accent);color:#fff;cursor:pointer;text-decoration:none;display:inline-block}
  button.ghost,a.ghost{background:transparent;color:var(--accent);border:1px solid var(--border)}
  button:disabled{opacity:.5}
  .drop{border:2px dashed var(--border);border-radius:var(--radius);padding:30px;text-align:center;color:var(--muted);transition:.15s}
  .drop.over{border-color:var(--accent);color:var(--accent)}
  .actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:6px}
  .empty{color:var(--muted);text-align:center;padding:20px}
  #pinGate{text-align:center}
  input[type=password]{font:inherit;padding:10px 14px;border:1px solid var(--border);border-radius:12px;background:var(--bg);color:var(--fg);width:180px;text-align:center;letter-spacing:4px}
  .hidden{display:none}
  #toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:var(--fg);color:var(--bg);padding:10px 18px;border-radius:20px;opacity:0;transition:.2s;pointer-events:none;font-size:14px}
  #toast.show{opacity:.95}
</style>
</head>
<body>
<div class="wrap">
  <h1>BIShare</h1>
  <p class="sub">$alias · files on your local network</p>

  <div id="pinGate" class="card ${pinEnabled ? '' : 'hidden'}">
    <p style="margin:4px 0 14px">This device is protected with a PIN.</p>
    <input id="pin" type="password" inputmode="numeric" placeholder="PIN" autofocus>
    <div style="margin-top:14px"><button onclick="verifyPin()">Unlock</button></div>
    <p id="pinErr" style="color:#ff453a;margin:12px 0 0;display:none">Wrong PIN</p>
  </div>

  <div id="app" class="${pinEnabled ? 'hidden' : ''}">
    <div class="card">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">
        <strong>Files</strong>
        <a id="dlAll" class="btn ghost" href="#" onclick="downloadAll(event)">Download all (.zip)</a>
      </div>
      <div id="files"><p class="empty">Loading…</p></div>
    </div>

    <div class="card">
      <strong>Send files to this device</strong>
      <div class="drop" id="drop" style="margin-top:12px" onclick="document.getElementById('file').click()">
        Drop files here, or tap to choose
      </div>
      <input id="file" type="file" multiple class="hidden">
      <div class="actions"><button id="upBtn" disabled onclick="upload()">Upload</button></div>
    </div>
  </div>
</div>
<div id="toast"></div>

<script>
  let token = null;
  const H = () => token ? {'X-Pin-Token': token} : {};
  const fmt = b => b<1024?b+' B':b<1048576?(b/1024).toFixed(1)+' KB':b<1073741824?(b/1048576).toFixed(1)+' MB':(b/1073741824).toFixed(2)+' GB';
  const toast = m => {const t=document.getElementById('toast');t.textContent=m;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),2000)};

  async function verifyPin(){
    const pin=document.getElementById('pin').value;
    const r=await fetch('/api/v1/verify-pin?pin='+encodeURIComponent(pin),{method:'POST'});
    if(r.ok){const j=await r.json();token=j.token||null;document.getElementById('pinGate').classList.add('hidden');document.getElementById('app').classList.remove('hidden');loadFiles();}
    else{document.getElementById('pinErr').style.display='block';}
  }

  async function loadFiles(){
    const box=document.getElementById('files');
    try{
      const r=await fetch('/api/v1/files',{headers:H()});
      if(!r.ok)throw 0;
      const files=await r.json();
      if(!files.length){box.innerHTML='<p class="empty">No files yet</p>';document.getElementById('dlAll').style.display='none';return;}
      document.getElementById('dlAll').style.display='inline-block';
      box.innerHTML=files.map(f=>`<div class="row"><div class="meta"><div class="name">\${f.fileName}</div><div class="size">\${fmt(f.size)}</div></div><a class="btn" href="#" onclick="dl(\${f.index},event)">Download</a></div>`).join('');
    }catch(e){box.innerHTML='<p class="empty">Could not load files</p>';}
  }

  function dl(i,e){e.preventDefault();const u='/api/v1/download?index='+i+(token?'&token='+token:'');window.location=u;}
  function downloadAll(e){e.preventDefault();window.location='/api/v1/download-all'+(token?'?token='+token:'');}

  const drop=document.getElementById('drop'),fileInput=document.getElementById('file'),upBtn=document.getElementById('upBtn');
  let picked=[];
  fileInput.onchange=()=>{picked=[...fileInput.files];drop.textContent=picked.length?picked.length+' file(s) ready':'Drop files here, or tap to choose';upBtn.disabled=!picked.length;};
  ['dragover','dragenter'].forEach(ev=>drop.addEventListener(ev,e=>{e.preventDefault();drop.classList.add('over');}));
  ['dragleave','drop'].forEach(ev=>drop.addEventListener(ev,e=>{e.preventDefault();drop.classList.remove('over');}));
  drop.addEventListener('drop',e=>{picked=[...e.dataTransfer.files];drop.textContent=picked.length+' file(s) ready';upBtn.disabled=!picked.length;});

  async function upload(){
    if(!picked.length)return;upBtn.disabled=true;let ok=0;
    for(const f of picked){
      const fd=new FormData();fd.append('file',f,f.name);
      try{const r=await fetch('/api/v1/browser-upload',{method:'POST',headers:H(),body:fd});if(r.ok)ok++;}catch(e){}
    }
    toast('Uploaded '+ok+' file(s)');picked=[];fileInput.value='';drop.textContent='Drop files here, or tap to choose';upBtn.disabled=true;
  }

  if(!$pinEnabled)loadFiles();
</script>
</body>
</html>''';
}
