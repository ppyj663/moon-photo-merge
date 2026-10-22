///|
extern "js" fn cli_args() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
extern "js" fn set_exit_code(code : Int32) -> Unit =
  #| (code) => { process.exitCode = code; }

///|
extern "js" fn file_name(relative : String) -> String =
  #| (relative) => require('node:path').posix.basename(relative)

///|
extern "js" fn file_ext(relative : String) -> String =
  #| (relative) => require('node:path').posix.extname(relative).toLowerCase()

///|
extern "js" fn file_parent(file : String) -> String =
  #| (file) => require('node:path').dirname(require('node:path').resolve(file))

///|
extern "js" fn report_path(folder : String) -> String =
  #| (folder) => require('node:path').resolve(folder, 'review.html')

///|
extern "js" fn incoming_relative(path : String) -> String =
  #| (path) => path.startsWith('incoming/') ? path.slice(9) : ''

///|
extern "js" fn match_url(
  path : String,
  library : String,
  incoming : String,
) -> String =
  #| (path, library, incoming) => {
  #|   const url = require('node:url');
  #|   const join = require('node:path').join;
  #|   if (path.startsWith('library/')) return url.pathToFileURL(join(library, path.slice(8))).href;
  #|   if (path.startsWith('incoming/')) return url.pathToFileURL(join(incoming, path.slice(9))).href;
  #|   return '';
  #| }

///|
extern "js" fn real_path(input : String) -> String =
  #| (input) => require('node:fs').realpathSync(input)

///|
/// Returns an error message or an empty string when all three paths are usable.
extern "js" fn validate_paths(
  library : String,
  incoming : String,
  report : String,
) -> String =
  #| (library, incoming, report) => {
  #|   const fs = require('node:fs');
  #|   const path = require('node:path');
  #|   try {
  #|     const old = fs.realpathSync(library);
  #|     const fresh = fs.realpathSync(incoming);
  #|     if (!fs.statSync(old).isDirectory() || !fs.statSync(fresh).isDirectory()) return '两个输入都必须是文件夹';
  #|     let pending = [];
  #|     let cursor = path.resolve(report);
  #|     while (!fs.existsSync(cursor)) {
  #|       pending.unshift(path.basename(cursor));
  #|       const parent = path.dirname(cursor);
  #|       if (parent === cursor) throw new Error('无法确定报告文件夹位置');
  #|       cursor = parent;
  #|     }
  #|     const out = path.join(fs.realpathSync(cursor), ...pending);
  #|     const norm = x => process.platform === 'win32' ? x.toLowerCase() : x;
  #|     const contains = (a, b) => norm(b) === norm(a) || norm(b).startsWith(norm(a + path.sep));
  #|     if (contains(old, fresh) || contains(fresh, old)) return '现有相册和待导入备份不能互相包含';
  #|     if (contains(old, out) || contains(fresh, out)) return '报告文件夹不能位于输入文件夹内';
  #|     if (contains(out, old) || contains(out, fresh)) return '输入文件夹不能位于报告文件夹内';
  #|     return '';
  #|   } catch (error) { return String(error.message); }
  #| }

///|
/// Does not follow directory or file symlinks.
extern "js" fn image_files(root : String) -> FixedArray[String] =
  #| (root) => {
  #|   const fs = require('node:fs');
  #|   const path = require('node:path');
  #|   const result = [];
  #|   const visit = (dir, relative) => {
  #|     for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
  #|       if (item.isSymbolicLink()) continue;
  #|       const rel = relative ? relative + '/' + item.name : item.name;
  #|       const full = path.join(dir, item.name);
  #|       if (item.isDirectory()) visit(full, rel);
  #|       else if (item.isFile() && /\.(jpe?g|png)$/i.test(item.name)) result.push(rel);
  #|     }
  #|   };
  #|   visit(fs.realpathSync(root), '');
  #|   return result.sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
  #| }

///|
/// Read errors become empty bytes; the scanner classifies those as unreadable.
extern "js" fn read_photo(root : String, relative : String) -> Bytes =
  #| (root, relative) => {
  #|   const fs = require('node:fs');
  #|   const path = require('node:path');
  #|   try {
  #|     const base = fs.realpathSync(root);
  #|     const name = path.resolve(base, relative);
  #|     const candidate = fs.realpathSync(name);
  #|     const check = process.platform === 'win32' ? x => x.toLowerCase() : x => x;
  #|     if (!check(candidate).startsWith(check(base + path.sep))) return new Uint8Array(0);
  #|     if (!fs.lstatSync(name).isFile()) return new Uint8Array(0);
  #|     return fs.readFileSync(name);
  #|   } catch (_) { return new Uint8Array(0); }
  #| }

///|
extern "js" fn sha256_bytes(data : Bytes) -> String =
  #| (data) => require('node:crypto').createHash('sha256').update(data).digest('hex')

///|
extern "js" fn sha256_text(data : String) -> String =
  #| (data) => require('node:crypto').createHash('sha256').update(data, 'utf8').digest('hex')

///|
extern "js" fn image_url(root : String, relative : String) -> String =
  #| (root, relative) => require('node:url').pathToFileURL(require('node:path').join(root, relative)).href

///|
extern "js" fn write_report(folder : String, html : String) -> String =
  #| (folder, html) => {
  #|   try {
  #|     const fs = require('node:fs');
  #|     const path = require('node:path');
  #|     fs.mkdirSync(folder, {recursive: true});
  #|     fs.writeFileSync(path.join(folder, 'review.html'), html, 'utf8');
  #|     return '';
  #|   } catch (error) { return String(error.message); }
  #| }

///|
extern "js" fn html_row(
  path : String,
  label : String,
  code : String,
  match_path : String,
  destination : String,
  size : Int32,
  source_url : String,
  candidate_url : String,
) -> String =
  #| (path, label, code, matchPath, destination, size, sourceUrl, candidateUrl) => {
  #|   const esc = x => String(x).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  #|   const preview = url => url ? `<img loading="lazy" src="${esc(url)}" alt="图片预览">` : '';
  #|   const selectable = code === 'new' || code === 'similar' || code === 'conflict';
  #|   const tick = selectable ? `<input type="checkbox" class="pick" data-path="${esc(path)}" ${code === 'new' ? 'checked' : ''} aria-label="导入 ${esc(path)}">` : '';
  #|   return `<tr data-kind="${esc(code)}"><td>${tick}</td><td>${preview(sourceUrl)}<div class="path">${esc(path)}</div></td><td><strong>${esc(label)}</strong></td><td>${preview(candidateUrl)}<div class="path">${esc(matchPath)}</div></td><td>${esc(destination)}</td><td>${esc((size / 1024).toFixed(1))} KB</td></tr>`;
  #| }

///|
extern "js" fn html_page(
  scan_id : String,
  rows : String,
  total : Int32,
  exact : Int32,
  similar : Int32,
  conflict : Int32,
  new_count : Int32,
  unreadable : Int32,
) -> String =
  #| (scanId, rows, total, exact, similar, conflict, newCount, unreadable) => {
  #|   const id = JSON.stringify(scanId);
  #|   return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>照片备份合并预检</title><style>
  #|   :root{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:#172136;background:#f3f5f9}body{margin:0}header{background:#15233d;color:white;padding:28px max(24px,5vw)}h1{font-size:26px;margin:0 0 8px}header p{margin:0;color:#ced8e8}main{max-width:1300px;margin:24px auto;padding:0 18px}.toolbar{display:flex;align-items:center;gap:12px;flex-wrap:wrap;background:white;border:1px solid #dbe2ec;border-radius:12px;padding:16px;margin-bottom:16px}button{border:0;border-radius:8px;background:#2457c5;color:white;padding:11px 16px;font-size:15px;cursor:pointer}button:hover{background:#173d94}button.secondary{background:#52627a}button.secondary:hover{background:#39485e}select{padding:9px;border:1px solid #bdc8d8;border-radius:7px}small{color:#57657c}.table-wrap{overflow:auto;background:white;border:1px solid #dbe2ec;border-radius:12px}table{width:100%;border-collapse:collapse;min-width:900px}th,td{padding:12px;text-align:left;border-bottom:1px solid #e7ebf1;vertical-align:top}th{background:#f8faff;position:sticky;top:0}td img{width:96px;height:72px;object-fit:contain;background:#eef1f5;border-radius:5px}.path{max-width:270px;overflow-wrap:anywhere;font-size:12px;color:#566278;margin-top:5px}tr[data-kind="exact"]{background:#f6f8fa}tr[data-kind="unreadable"]{background:#fff6f3}.note{line-height:1.6;color:#45536b;margin:14px 0 22px}.count{font-weight:700}.summary{flex-basis:100%;font-size:13px;color:#45536b}</style></head><body><header><h1>照片备份合并预检</h1><p>先看差异，再决定复制哪些照片。原文件不会被删除或覆盖。</p></header><main><div class="toolbar"><span class="count">待导入图片 ${total} 张</span><span class="summary" id="summary" data-exact="${exact}" data-similar="${similar}" data-conflict="${conflict}" data-new="${newCount}" data-unreadable="${unreadable}">完全重复 ${exact} · 疑似相似 ${similar} · 同名冲突 ${conflict} · 可新增 ${newCount} · 无法解码 ${unreadable}</span><label>筛选 <select id="filter"><option value="all">全部</option><option value="new">可新增</option><option value="similar">疑似相似</option><option value="conflict">同名冲突</option><option value="exact">完全重复</option><option value="unreadable">无法解码</option></select></label><button id="select-new">只选可新增</button><button id="clear-selection" class="secondary">清空选择</button><button id="download">下载审核清单</button><small id="selected"></small></div><p class="note">“可新增”默认勾选；疑似相似与同名冲突需要手动勾选。完全重复和无法解码的文件不能选。下载清单后，在命令行执行 apply。预检不会改动现有相册。</p><div class="table-wrap"><table><thead><tr><th>选择</th><th>待导入照片</th><th>判断</th><th>参考照片</th><th>建议目标文件名</th><th>大小</th></tr></thead><tbody>${rows}</tbody></table></div></main><script>
  #|   const scanId=${id};const picks=[...document.querySelectorAll('.pick')];const selected=document.getElementById('selected');function update(){selected.textContent='已选 '+picks.filter(x=>x.checked).length+' 张';}picks.forEach(x=>x.addEventListener('change',update));update();document.getElementById('select-new').addEventListener('click',()=>{picks.forEach(x=>x.checked=x.closest('tr').dataset.kind==='new');update();});document.getElementById('clear-selection').addEventListener('click',()=>{picks.forEach(x=>x.checked=false);update();});document.getElementById('filter').addEventListener('change',e=>{document.querySelectorAll('tbody tr').forEach(row=>row.hidden=e.target.value!=='all'&&row.dataset.kind!==e.target.value);});document.getElementById('download').addEventListener('click',()=>{const data={scanId,selected:picks.filter(x=>x.checked).map(x=>x.dataset.path)};const link=document.createElement('a');link.href=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));link.download='approved.json';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000);});
  #|   </script></body></html>`;
  #| }

///|
extern "js" fn approved_error(file : String) -> String =
  #| (file) => {
  #|   try {
  #|     const value = JSON.parse(require('node:fs').readFileSync(file, 'utf8'));
  #|     if (!value || typeof value !== 'object' || Array.isArray(value)) return '审核清单必须是 JSON 对象';
  #|     if (typeof value.scanId !== 'string' || !/^[a-f0-9]{64}$/.test(value.scanId)) return '审核清单缺少有效 scanId';
  #|     if (!Array.isArray(value.selected)) return '审核清单中的 selected 必须是数组';
  #|     if (!value.selected.every(x => typeof x === 'string')) return '审核清单中的 selected 只能包含文件路径字符串';
  #|     return '';
  #|   } catch (_) { return '审核清单不是有效 JSON'; }
  #| }

///|
extern "js" fn approved_scan_id(file : String) -> String =
  #| (file) => {
  #|   try { const value = JSON.parse(require('node:fs').readFileSync(file, 'utf8')); return typeof value.scanId === 'string' ? value.scanId : ''; }
  #|   catch (_) { return ''; }
  #| }

///|
extern "js" fn approved_paths(file : String) -> FixedArray[String] =
  #| (file) => {
  #|   try { const value = JSON.parse(require('node:fs').readFileSync(file, 'utf8')); return Array.isArray(value.selected) ? value.selected.filter(x => typeof x === 'string') : []; }
  #|   catch (_) { return []; }
  #| }

///|
/// Copy into a same-directory temp file, verify it, then publish with a hard
/// link. The link fails if the final name already exists; originals stay intact.
extern "js" fn safe_copy(
  source_root : String,
  relative : String,
  target_root : String,
  name : String,
  expected : String,
) -> String =
  #| (source_root, relative, target_root, name, expected) => {
  #|   const fs = require('node:fs');
  #|   const path = require('node:path');
  #|   const crypto = require('node:crypto');
  #|   const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
  #|   let temp = '';
  #|   try {
  #|     if (!name || name === '.' || name === '..' || path.basename(name) !== name) throw new Error('目标文件名无效');
  #|     const base = fs.realpathSync(source_root);
  #|     const source = fs.realpathSync(path.resolve(base, relative));
  #|     const check = process.platform === 'win32' ? x => x.toLowerCase() : x => x;
  #|     if (!check(source).startsWith(check(base + path.sep)) || !fs.lstatSync(source).isFile()) throw new Error('来源文件无效');
  #|     const target = fs.realpathSync(target_root);
  #|     const final = path.join(target, name);
  #|     if (fs.existsSync(final)) throw new Error('目标文件名已存在');
  #|     if (hash(source) !== expected) throw new Error('来源内容与预览时不同');
  #|     temp = path.join(target, '.photo-merge-' + crypto.randomUUID() + '.tmp');
  #|     fs.copyFileSync(source, temp, fs.constants.COPYFILE_EXCL);
  #|     if (hash(temp) !== expected) throw new Error('复制后的校验未通过');
  #|     fs.linkSync(temp, final);
  #|     return '';
  #|   } catch (error) { return String(error.message); }
  #|   finally { if (temp && fs.existsSync(temp)) fs.unlinkSync(temp); }
  #| }
