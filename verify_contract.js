/*
 * 验证手机 App 设计的 API 契约与业务逻辑，用真实后端跑。
 * 模拟四个操作：上传 -> 列表可见 -> 下载 -> 删除，并检查墓碑/回收站。
 * 不写用户数据：用独立的测试 DATA_DIR。
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');

const WORK = 'C:/Users/user/WorkBuddy/2026-10-29-19-49-32/桌面APP_工作副本/app';
const NODE = 'C:/Users/user/.workbuddy/binaries/node/versions/22.22.2-2/node.exe';
const TESTDIR = fs.mkdtempSync(path.join(os.tmpdir(), 'xkmobile-verify-'));
const PORT = 18877;
const BASE = `http://127.0.0.1:${PORT}`;

const sleep = ms => new Promise(r => setTimeout(r, ms));

function req(method, urlPath, body, isBinary) {
  return new Promise((resolve, reject) => {
    const data = body == null ? null :
      (isBinary ? body : Buffer.from(JSON.stringify(body), 'utf8'));
    const opts = {
      hostname: '127.0.0.1', port: PORT, path: urlPath, method,
      headers: data ? {
        'Content-Type': isBinary ? 'application/octet-stream' : 'application/json',
        'Content-Length': data.length
      } : {}
    };
    const r = http.request(opts, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const buf = Buffer.concat(chunks);
        let json = null;
        try { json = JSON.parse(buf.toString('utf8')); } catch (e) {}
        resolve({ status: res.statusCode, buf, json });
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

function assert(cond, msg) {
  if (!cond) { console.log('  FAIL:', msg); process.exitCode = 1; throw new Error(msg); }
  console.log('  OK:', msg);
}

(async () => {
  // 1) 启动真实后端（独立数据目录）
  const child = spawn(NODE, [path.join(WORK, '后端server.js')], {
    env: {
      ...process.env,
      PORT: String(PORT),
      DATA_DIR: TESTDIR,
      BACKUP_DIR: path.join(TESTDIR, 'backup'),
      XK_CLOUD_UPSTREAM: 'none',
      XK_AUTO_EXIT: '0'
    },
    stdio: 'ignore'
  });

  let up = false;
  for (let i = 0; i < 40; i++) {
    try { const r = await req('GET', '/api/ping'); if (r.status === 200) { up = true; break; } }
    catch (e) {}
    await sleep(150);
  }
  assert(up, '后端启动成功');
  if (!up) { child.kill(); process.exit(1); }

  try {
    // 2) 上传：写 blob + 写元数据（来源=手机、分类=速传）
    console.log('\n[上传]');
    const fid = 'f_test123456';
    const content = Buffer.from('这是手机上传的测试文件内容 abc 123', 'utf8');
    const rr = await req('PUT', `/api/blob/${fid}`, content, true);
    assert(rr.status === 200 && rr.json.ok, 'blob 写入成功');

    const props = {
      '实体ID': { text: fid },
      '项目ID': { text: '' },
      '名称': { text: '现场照片.pdf' },
      '分类': { text: '速传' },
      '类型': { text: '文件' },
      '文件类型': { text: 'binary' },
      '大小': { number: content.length },
      'MIME': { text: 'application/pdf' },
      '存储位置': { text: 'blob' },
      '相对路径': { text: '' },
      '来源': { text: '手机' },
      '更新时间': { date: new Date().toISOString() }
    };
    const meta = await req('PUT', `/api/store/file_${fid}`, { id: fid, props });
    assert(meta.status === 200 && meta.json.ok, '元数据写入成功');

    // 3) 列表：前缀查询能拿到，字段解析正确
    console.log('\n[列表]');
    const list = await req('GET', '/api/store/x?prefix=file_');
    assert(list.status === 200 && Array.isArray(list.json), '前缀列表返回数组');
    const found = list.json.find(x => x.id === fid || (x.props && x.props['实体ID'] && x.props['实体ID'].text === fid));
    assert(!!found, '列表能找到刚上传的文件');
    assert(found.props['来源'].text === '手机', '来源字段 = 手机（电脑端手机上传页据此显示）');
    assert(found.props['分类'].text === '速传', '分类字段 = 速传');

    // 4) ping 变更检测
    console.log('\n[变更检测]');
    const ping = await req('GET', '/api/ping?prefix=file_');
    assert(ping.status === 200 && ping.json.latest > 0, 'ping 返回 latest 时间戳');

    // 5) 下载：字节一致
    console.log('\n[下载]');
    const dl = await req('GET', `/api/blob/${fid}`);
    assert(dl.status === 200 && dl.buf.equals(content), '下载字节与上传一致');

    // 6) 删除：写回收站 + 墓碑 + 删元数据，但不删 blob
    console.log('\n[删除]');
    const recycleProps = {
      '实体ID': { text: fid },
      '删除时间': { date: new Date().toISOString() },
      '名称': { text: '现场照片.pdf' },
      '来源': { text: '手机' },
      '存储位置': { text: 'blob' }
    };
    const rec = await req('PUT', `/api/store/recycle_${fid}`, { id: `recycle_${fid}`, props: recycleProps });
    assert(rec.status === 200, '回收站记录写入成功');
    const tomb = await req('PUT', `/api/store/tombstone_file_${fid}`, {
      id: `tombstone_file_${fid}`,
      props: { '实体ID': { text: fid }, '类型': { text: 'file' }, '删除时间': { date: new Date().toISOString() } }
    });
    assert(tomb.status === 200, '墓碑写入成功');
    const del = await req('DELETE', `/api/store/file_${fid}`);
    assert(del.status === 200, '元数据删除成功');

    const list2 = await req('GET', '/api/store/x?prefix=file_');
    const stillThere = list2.json.find(x => (x.props && x.props['实体ID'] && x.props['实体ID'].text === fid));
    assert(!stillThere, '删除后列表里不再有该文件');

    const blobStill = await req('GET', `/api/blob/${fid}`);
    assert(blobStill.status === 200 && blobStill.buf.equals(content), 'blob 内容仍保留（7天可恢复的关键）');

    const recycleList = await req('GET', '/api/store/x?prefix=recycle_');
    assert(recycleList.json.some(x => x.id === `recycle_${fid}`), '回收站里能查到（两端同步恢复依据）');

    console.log('\n=== 契约验证全部通过 ===');
  } finally {
    child.kill();
    fs.rmSync(TESTDIR, { recursive: true, force: true });
  }
})().catch(e => { console.error('验证中断:', e.message); process.exit(1); });
