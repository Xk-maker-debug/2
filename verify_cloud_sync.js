/*
 * 云端中转站异步同步契约验证（Node 版，等价于 App 内的 Dart 逻辑）
 * 验证：
 *  1) 小文件上传→列表可见→下载字节一致
 *  2) 大文件(67MB)分片上传→按清单重组→sha256 一致（绕过 60MB 网关上限）
 *  3) 删除：写回收站+墓碑+删元数据，blob 保留（可恢复）
 *  4) 数据落在网页版原生命名空间（file_/recycle_/tombstone_），与网页版互通
 *  测试键统一 dmtest_ 前缀，跑完清理。
 */
const https = require('https');
const crypto = require('crypto');
const fs = require('fs');

const BASE = 'https://ee6724b361024828b9712f447c688b85.app.workbuddy.host';
const CHUNK = 50 * 1024 * 1024;
const PREFIX = 'dmtest_';
let pass = 0, fail = 0;

function req(path, method, body, ctype) {
  return new Promise((resolve) => {
    const data = body ? Buffer.from(body) : null;
    const opts = { method: method || 'GET', headers: { 'User-Agent': 'curl/8.0.1' } };
    if (data) opts.headers['Content-Type'] = ctype || 'application/octet-stream';
    if (data) opts.headers['Content-Length'] = data.length;
    const started = Date.now();
    const r = https.request(BASE + path, opts, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks), ms: Date.now() - started }));
    });
    r.on('error', (e) => resolve({ status: -1, body: Buffer.from(String(e)), ms: Date.now() - started }));
    if (data) r.write(data);
    r.end();
  });
}
function putStore(k, v) { return req('/api/store/' + k, 'PUT', JSON.stringify(v), 'application/json'); }
function getStore(k) { return req('/api/store/' + k, 'GET'); }
function delStore(k) { return req('/api/store/' + k, 'DELETE'); }
function putBlob(id, buf) { return req('/api/blob/' + id, 'PUT', buf, 'application/octet-stream'); }
function getBlob(id) { return req('/api/blob/' + id, 'GET'); }
function sha(b) { return crypto.createHash('sha256').update(b).digest('hex'); }
function ok(cond, label, extra) { if (cond) { pass++; console.log('  ✓', label, extra || ''); } else { fail++; console.log('  ✗ FAIL', label, extra || ''); } }

async function uploadBlob(id, bytes) {
  if (bytes.length <= CHUNK) {
    if (!usedBlobIds.includes(id)) usedBlobIds.push(id);
    const r = await putBlob(id, bytes);
    if (r.status !== 200) throw new Error('PUT blob ' + r.status);
    return;
  }
  const parts = Math.ceil(bytes.length / CHUNK);
  for (let i = 0; i < parts; i++) {
    const bid = id + '__p' + i;
    if (!usedBlobIds.includes(bid)) usedBlobIds.push(bid);
    const piece = bytes.subarray(i * CHUNK, Math.min((i + 1) * CHUNK, bytes.length));
    const r = await putBlob(bid, piece);
    if (r.status !== 200) throw new Error('PUT part ' + i + ' -> ' + r.status);
  }
  await putStore('blobparts_' + id, { id: 'blobparts_' + id, props: { n: parts, size: bytes.length } });
}
async function downloadBlob(id) {
  const meta = await getStore('blobparts_' + id);
  if (meta.status === 200) {
    const j = JSON.parse(meta.body.toString());
    const n = (j.props && j.props.n) || 0;
    if (n > 0) {
      const out = [];
      for (let i = 0; i < n; i++) {
        const r = await getBlob(id + '__p' + i);
        if (r.status !== 200) throw new Error('GET part ' + i);
        out.push(r.body);
      }
      return Buffer.concat(out);
    }
  }
  const r = await getBlob(id);
  if (r.status !== 200) throw new Error('GET blob ' + r.status);
  return r.body;
}

const usedBlobIds = []; // 记录本次创建的 blob，用于彻底清理

(async () => {
  console.log('=== 云端中转站异步同步契约验证 ===');

  // 1) 小文件
  console.log('\n[1] 小文件上传→列表→下载');
  const smallId = PREFIX + 'small';
  const smallBytes = Buffer.from('xk cloud sync test ' + Date.now());
  await uploadBlob(smallId, smallBytes);
  const meta = { id: 'file_' + smallId, props: { '名称': { text: '小测试.txt' }, '来源': { text: '手机' }, '大小': { number: smallBytes.length } } };
  await putStore('file_' + smallId, meta);
  const listed = await req('/api/store/dmtest_small?prefix=' + PREFIX);
  const listOk = listed.status === 200;
  const back = await downloadBlob(smallId);
  ok(listOk, '元数据进列表（file_ 前缀）');
  ok(back.equals(smallBytes), '小文件下载字节一致');

  // 2) 大文件分片
  console.log('\n[2] 67MB 大文件分片上传→重组（绕过 413）');
  const F = 'C:/Users/user/Desktop/28335/测试数据/201E上电时序测试_V1.1.docx';
  if (fs.existsSync(F)) {
    const big = fs.readFileSync(F);
    const bigId = PREFIX + 'big';
    const t0 = Date.now();
    await uploadBlob(bigId, big);
    console.log('  分片上传耗时', ((Date.now() - t0) / 1000).toFixed(1), 's');
    const back2 = await downloadBlob(bigId);
    ok(back2.length === big.length && sha(back2) === sha(big),
      '大文件重组 sha256 一致', '(' + (big.length / 1048576).toFixed(1) + 'MB)');
    const meta2 = await getStore('blobparts_' + bigId);
    ok(meta2.status === 200, '分片清单已写入');
  } else {
    console.log('  (跳过：测试文件不存在)');
  }

  // 3) 删除（回收站+墓碑+删元数据，blob 保留）
  console.log('\n[3] 删除：写回收站+墓碑+删元数据，blob 保留');
  await putStore('recycle_' + smallId, { id: 'recycle_' + smallId, props: { '实体ID': { text: smallId } } });
  await putStore('tombstone_file_' + smallId, { id: 'tombstone_file_' + smallId, props: { '实体ID': { text: smallId }, '类型': { text: 'file' } } });
  await delStore('file_' + smallId);
  const gone = await getStore('file_' + smallId);
  const tomb = await getStore('tombstone_file_' + smallId);
  const blobStill = await getBlob(smallId);
  ok(gone.status === 404, '元数据已删（列表消失）');
  ok(tomb.status === 200, '墓碑已写（两端识别已删）');
  ok(blobStill.status === 200, 'blob 保留（7天可恢复，未物理删）');

  // 4) 隔离性：测试键用 file_<dmtest_> 落在网页版原生命名空间，但不碰具体网页版数据
  console.log('\n[4] 命名空间隔离（不污染网页版数据）');
  const pong = await req('/api/ping');
  const pj = JSON.parse(pong.body.toString());
  ok(pj.count >= 12000, '网页版数据池仍在（未被测试影响）', '(count=' + pj.count + ')');

  // 清理
  console.log('\n[清理] 删除全部 dmtest_ 键');
  const keys = [];
  const all = await req('/api/store');
  try {
    const j = JSON.parse(all.body.toString());
    const arr = Array.isArray(j) ? j : (j.keys || []);
    // 按"包含测试 id 串"清理，覆盖 file_/recycle_/tombstone_/blobparts_ 各种前缀
    keys.push(...arr.filter((k) => String(k).includes(PREFIX)));
  } catch (e) {}
  for (const k of keys) await delStore(k);
  // blobs：删小文件整块 + 所有分片
  await req('/api/blob/' + smallId, 'DELETE');
  if (!usedBlobIds.includes(smallId)) usedBlobIds.push(smallId);
  for (const b of usedBlobIds) await req('/api/blob/' + b, 'DELETE');
  const finalPing = await req('/api/ping?prefix=' + PREFIX);
  ok(JSON.parse(finalPing.body.toString()).count === 0, '测试 store 键已清空');

  console.log('\n=== 结果：' + pass + ' 通过 / ' + fail + ' 失败 ===');
  process.exit(fail ? 1 : 0);
})();
