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
/// (inline CSS + JS — CSP-friendly), dark-mode aware, optional PIN gate. Lets
/// any browser on the LAN download this device's files and upload files to it —
/// no app needed.
///
/// Feature #11 adds: a folder tree (browse + per-folder streaming zip download),
/// chunked resumable uploads (8 MB slices, `localStorage`-persisted upload ids
/// so a killed tab resumes where it left off), per-file progress bars, and
/// folder uploads (webkitdirectory picker + drag-and-drop traversal).
///
/// NOTE ON LANGUAGE: the page's strings are deliberately English-only. It is
/// served to arbitrary external browsers, outside the app's easy_localization
/// runtime — this matches the page's existing convention (all prior strings
/// here are English literals).
String browserPageHtml({
  required String alias,
  required bool pinEnabled,
  required bool uploadEnabled,
}) {
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
  .row.dir .name{cursor:pointer;color:var(--accent)}
  a.btn,button{font:inherit;font-weight:600;border:none;border-radius:12px;padding:10px 16px;background:var(--accent);color:#fff;cursor:pointer;text-decoration:none;display:inline-block}
  button.ghost,a.ghost{background:transparent;color:var(--accent);border:1px solid var(--border)}
  button.small,a.small{padding:6px 12px;font-size:13px;border-radius:10px}
  button:disabled{opacity:.5}
  .crumb{font-size:13px;color:var(--muted);margin:2px 0 8px;white-space:nowrap;overflow-x:auto}
  .crumb a{color:var(--accent);text-decoration:none;cursor:pointer}
  .drop{border:2px dashed var(--border);border-radius:var(--radius);padding:30px;text-align:center;color:var(--muted);transition:.15s;cursor:pointer}
  .drop.over{border-color:var(--accent);color:var(--accent)}
  .actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:10px}
  .empty{color:var(--muted);text-align:center;padding:20px}
  .uprow{display:flex;align-items:center;gap:12px;padding:10px 4px;border-bottom:1px solid var(--border)}
  .uprow:last-child{border-bottom:none}
  .uprow .meta{flex:1;min-width:0}
  .upbar{height:5px;border-radius:3px;background:var(--border);margin-top:6px;overflow:hidden}
  .upbar i{display:block;height:100%;width:0;background:var(--accent);border-radius:3px;transition:width .15s}
  .uprow.err .upbar i{background:#ff453a}
  .upst{font-size:12px;color:var(--muted);min-width:38px;text-align:right}
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
        <a id="dlAll" class="btn ghost small" href="#" onclick="downloadAll(event)">Download all (.zip)</a>
      </div>
      <div id="files"><p class="empty">Loading…</p></div>
    </div>

    <div id="folders" class="card hidden">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:2px">
        <strong>Folders</strong>
        <a id="dlCur" class="btn ghost small" href="#" onclick="dlFolder(cur,event)">Download folder (.zip)</a>
      </div>
      <div id="crumb" class="crumb"></div>
      <div id="tree"></div>
    </div>

    <div class="card ${uploadEnabled ? '' : 'hidden'}">
      <strong>Send files to this device</strong>
      <div class="drop" id="drop" style="margin-top:12px">
        Drop files or folders here, or tap to choose
      </div>
      <input id="file" type="file" multiple class="hidden">
      <input id="dirpick" type="file" webkitdirectory class="hidden">
      <div id="queue"></div>
      <div class="actions">
        <button id="upBtn" disabled onclick="upload()">Upload</button>
        <button class="ghost" onclick="document.getElementById('dirpick').click()">Choose folder</button>
      </div>
    </div>
  </div>
</div>
<div id="toast"></div>

<script>
  var token=null;
  var CHUNK=8*1024*1024;
  function H(){return token?{'X-Pin-Token':token}:{};}
  function el(id){return document.getElementById(id);}
  function fmt(b){return b<1024?b+' B':b<1048576?(b/1024).toFixed(1)+' KB':b<1073741824?(b/1048576).toFixed(1)+' MB':(b/1073741824).toFixed(2)+' GB';}
  function esc(s){return String(s).replace(/[&<>"']/g,function(c){return '&#'+c.charCodeAt(0)+';';});}
  function tok(sep){return token?sep+'token='+encodeURIComponent(token):'';}
  function toast(m){var t=el('toast');t.textContent=m;t.classList.add('show');setTimeout(function(){t.classList.remove('show');},2200);}

  async function verifyPin(){
    var pin=el('pin').value;
    var r=await fetch('/api/v1/verify-pin?pin='+encodeURIComponent(pin),{method:'POST'});
    if(r.ok){var j=await r.json();token=j.token||null;el('pinGate').classList.add('hidden');el('app').classList.remove('hidden');init();}
    else{el('pinErr').style.display='block';}
  }
  el('pin').addEventListener('keydown',function(e){if(e.key==='Enter')verifyPin();});

  function init(){loadFiles();browse('');}

  // ---- flat file list ----
  async function loadFiles(){
    var box=el('files');
    try{
      var r=await fetch('/api/v1/files',{headers:H()});
      if(!r.ok)throw 0;
      var files=await r.json();
      if(!files.length){box.innerHTML='<p class="empty">No files yet</p>';el('dlAll').style.display='none';return;}
      el('dlAll').style.display='inline-block';
      box.innerHTML=files.map(function(f){
        return '<div class="row"><div class="meta"><div class="name">'+esc(f.fileName)+'</div><div class="size">'+fmt(f.size)+'</div></div>'+
               '<a class="btn small" href="#" onclick="dl('+f.index+',event)">Download</a></div>';
      }).join('');
    }catch(e){box.innerHTML='<p class="empty">Could not load files</p>';}
  }
  function dl(i,e){e.preventDefault();location='/api/v1/download?index='+i+tok('&');}
  function downloadAll(e){e.preventDefault();location='/api/v1/download-all'+tok('?');}

  // ---- folder tree ----
  var cur='';
  async function browse(path){
    try{
      var r=await fetch('/api/v1/browse?path='+encodeURIComponent(path),{headers:H()});
      if(!r.ok)throw 0;
      var j=await r.json();
      cur=path;
      renderTree(j);
      if(path===''&&!j.dirs.length&&!j.files.length){el('folders').classList.add('hidden');}
      else{el('folders').classList.remove('hidden');}
    }catch(e){
      if(path==='')el('folders').classList.add('hidden');
      else toast('Could not open folder');
    }
  }
  function renderTree(j){
    var crumb=el('crumb');crumb.textContent='';
    var home=document.createElement('a');home.textContent='Home';home.onclick=function(){browse('');};
    crumb.appendChild(home);
    var parts=cur?cur.split('/'):[];
    var acc='';
    parts.forEach(function(p){
      acc=acc?acc+'/'+p:p;var target=acc;
      crumb.appendChild(document.createTextNode(' / '));
      var a=document.createElement('a');a.textContent=p;a.onclick=function(){browse(target);};
      crumb.appendChild(a);
    });
    el('dlCur').style.display=cur?'inline-block':'none';
    var tree=el('tree');tree.textContent='';
    if(!j.dirs.length&&!j.files.length){tree.innerHTML='<p class="empty">Empty folder</p>';return;}
    j.dirs.forEach(function(d){
      var path=cur?cur+'/'+d:d;
      var row=document.createElement('div');row.className='row dir';
      var meta=document.createElement('div');meta.className='meta';
      var name=document.createElement('div');name.className='name';name.textContent='📁 '+d;
      name.onclick=function(){browse(path);};
      meta.appendChild(name);row.appendChild(meta);
      var zip=document.createElement('a');zip.className='btn ghost small';zip.textContent='.zip';
      zip.href='#';zip.onclick=function(e){e.preventDefault();dlFolder(path);};
      row.appendChild(zip);tree.appendChild(row);
    });
    j.files.forEach(function(f){
      var path=cur?cur+'/'+f.name:f.name;
      var row=document.createElement('div');row.className='row';
      var meta=document.createElement('div');meta.className='meta';
      var name=document.createElement('div');name.className='name';name.textContent=f.name;
      var size=document.createElement('div');size.className='size';size.textContent=fmt(f.size);
      meta.appendChild(name);meta.appendChild(size);row.appendChild(meta);
      var a=document.createElement('a');a.className='btn small';a.textContent='Download';
      a.href='#';a.onclick=function(e){e.preventDefault();location='/api/v1/download-file?path='+encodeURIComponent(path)+tok('&');};
      row.appendChild(a);tree.appendChild(row);
    });
  }
  function dlFolder(path,e){if(e)e.preventDefault();location='/download-folder?path='+encodeURIComponent(path)+tok('&');}

  // ---- chunked resumable upload ----
  var queue=[];
  var drop=el('drop'),fileInput=el('file'),dirInput=el('dirpick'),upBtn=el('upBtn');
  function relOf(f){return f.relPath||f.webkitRelativePath||f.name;}
  function addFiles(list){
    for(var i=0;i<list.length;i++){
      var f=list[i];
      queue.push({file:f,rel:relOf(f),frac:0,failed:false});
    }
    renderQueue();
  }
  function renderQueue(){
    var box=el('queue');box.textContent='';
    queue.forEach(function(q){
      var row=document.createElement('div');row.className='uprow'+(q.failed?' err':'');
      var meta=document.createElement('div');meta.className='meta';
      var name=document.createElement('div');name.className='name';name.textContent=q.rel;
      var bar=document.createElement('div');bar.className='upbar';
      var fill=document.createElement('i');fill.style.width=(q.frac*100).toFixed(1)+'%';
      bar.appendChild(fill);meta.appendChild(name);meta.appendChild(bar);
      var st=document.createElement('div');st.className='upst';
      st.textContent=q.failed?'retry':Math.round(q.frac*100)+'%';
      row.appendChild(meta);row.appendChild(st);
      q._fill=fill;q._st=st;q._row=row;
      box.appendChild(row);
    });
    upBtn.disabled=!queue.length;
    drop.textContent=queue.length?queue.length+' file(s) ready':'Drop files or folders here, or tap to choose';
  }
  function setFrac(q,frac){q.frac=frac;if(q._fill){q._fill.style.width=(frac*100).toFixed(1)+'%';q._st.textContent=Math.round(frac*100)+'%';}}

  drop.addEventListener('click',function(){fileInput.click();});
  fileInput.onchange=function(){addFiles(fileInput.files);fileInput.value='';};
  dirInput.onchange=function(){addFiles(dirInput.files);dirInput.value='';};
  ['dragover','dragenter'].forEach(function(ev){drop.addEventListener(ev,function(e){e.preventDefault();drop.classList.add('over');});});
  ['dragleave','drop'].forEach(function(ev){drop.addEventListener(ev,function(e){e.preventDefault();drop.classList.remove('over');});});
  drop.addEventListener('drop',async function(e){
    var items=e.dataTransfer.items,out=[],usedEntries=false;
    if(items&&items.length&&items[0].webkitGetAsEntry){
      var entries=[];
      for(var i=0;i<items.length;i++){var en=items[i].webkitGetAsEntry();if(en)entries.push(en);}
      if(entries.length){usedEntries=true;for(var k=0;k<entries.length;k++)await gather(entries[k],'',out);}
    }
    addFiles(usedEntries?out:e.dataTransfer.files);
  });
  // Recursively collect File objects (with relative paths) from a dropped
  // FileSystemEntry — this is what makes folder DROP work.
  function gather(entry,prefix,out){
    return new Promise(function(res){
      if(entry.isFile){
        entry.file(function(f){f.relPath=prefix+f.name;out.push(f);res();},function(){res();});
      }else if(entry.isDirectory){
        var rd=entry.createReader(),all=[];
        var next=function(){rd.readEntries(async function(es){
          if(!es.length){for(var i=0;i<all.length;i++)await gather(all[i],prefix+entry.name+'/',out);res();}
          else{for(var i=0;i<es.length;i++)all.push(es[i]);next();}
        },function(){res();});};
        next();
      }else res();
    });
  }

  function newId(){
    if(crypto&&crypto.randomUUID)return crypto.randomUUID();
    return 'u'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,12);
  }
  // One file: sequential 8 MB chunks, offset-checked by the server (409 → jump
  // to the offset actually on disk), 4 tries per chunk with backoff. The
  // uploadId persists in localStorage keyed by file identity, so re-picking
  // the same file after a tab kill resumes from the server's .part length.
  async function uploadOne(q){
    var f=q.file,rel=q.rel;
    var key='bishare-up:'+rel+':'+f.size+':'+f.lastModified;
    var id=localStorage.getItem(key);
    if(!id){id=newId();try{localStorage.setItem(key,id);}catch(e){}}
    var off=0;
    try{var s=await fetch('/api/v1/browser-upload-status?id='+encodeURIComponent(id),{headers:H()});if(s.ok)off=(await s.json()).offset||0;}catch(e){}
    if(off>f.size)off=0;
    for(;;){
      var end=Math.min(off+CHUNK,f.size);
      var last=end>=f.size;
      var hd=H();
      hd['X-Upload-Id']=id;hd['X-Chunk-Offset']=''+off;
      hd['X-File-Name']=encodeURIComponent(rel);hd['X-File-Size']=''+f.size;hd['X-File-Type']=f.type||'';
      if(last)hd['X-Upload-Complete']='1';
      var r=null,attempt=0;
      for(;;){
        try{r=await fetch('/api/v1/browser-upload-chunk',{method:'POST',headers:hd,body:f.slice(off,end)});}catch(e){r=null;}
        if(r&&(r.ok||r.status===409||r.status===413||r.status===403||r.status===507))break;
        if(++attempt>3)throw new Error('network');
        await new Promise(function(res){setTimeout(res,600*attempt*attempt);});
      }
      if(r.status===409){var j=await r.json();off=Math.min(j.expected||0,f.size);setFrac(q,f.size?off/f.size:0);continue;}
      if(r.status===413){try{localStorage.removeItem(key);}catch(e){}throw new Error('File too large');}
      if(r.status===403){throw new Error('Uploads not allowed');}
      if(r.status===507){throw new Error('Server storage full — try again later');}
      off=end;setFrac(q,f.size?off/f.size:1);
      if(last){try{localStorage.removeItem(key);}catch(e){}return;}
    }
  }
  async function upload(){
    if(!queue.length)return;
    upBtn.disabled=true;
    var ok=0,fail=0;
    for(var i=0;i<queue.length;i++){
      var q=queue[i];
      try{q.failed=false;await uploadOne(q);ok++;q.done=true;}
      catch(e){fail++;q.failed=true;if(q._row)q._row.className='uprow err';if(q._st)q._st.textContent='retry';}
    }
    queue=queue.filter(function(q){return !q.done;});
    renderQueue();
    toast(fail?('Uploaded '+ok+', failed '+fail+' — press Upload to retry'):('Uploaded '+ok+' file(s)'));
    loadFiles();browse(cur);
  }

  if(!$pinEnabled)init();
</script>
</body>
</html>''';
}
