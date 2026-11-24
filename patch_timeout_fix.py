# -*- coding: utf-8 -*-
"""
修复 timeout 编译错误：http 包的 get/put/delete 从不接受 timeout 命名参数。
方案：删除所有 timeout: 参数。
- 单行 `http.get(url, timeout: X)` -> `http.get(url)`
- 独立一行 `timeout: X,` -> 删除该行
底层 dart:io HttpClient 有系统级连接超时，配合 AppConfig 云端 0.5s 响应，足够。
保持 UTF-8 BOM + 换行风格。
"""
import re
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
BOM = b'\xef\xbb\xbf'
p = os.path.join(ROOT, 'lib', 'api', 'api_client.dart')

b = open(p, 'rb').read()
has_bom = b.startswith(BOM)
s = b.decode('utf-8-sig')
nl = '\r\n' if '\r\n' in s else '\n'
s_lf = s.replace('\r\n', '\n')

# 1) 单行内的 `, timeout: EXPR)` -> `)`  （匹配到最近的 ) 前的 timeout 参数）
before = s_lf
s_lf = re.sub(r',\s*timeout:\s*[^,()\n]+(?=\))', '', s_lf)
n_inline = len(before.split('timeout:')) - len(s_lf.split('timeout:'))

# 2) 独占一行的 timeout 参数 -> 删除整行
lines = s_lf.split('\n')
out = []
removed = []
for ln in lines:
    if re.match(r'^\s*timeout:\s*', ln):
        removed.append(ln.strip())
        continue
    out.append(ln)
s_lf = '\n'.join(out)

if nl == '\r\n':
    s_lf = s_lf.replace('\n', '\r\n')
o = s_lf.encode('utf-8')
if has_bom:
    o = BOM + o
open(p, 'wb').write(o)

print('单行删除数:', n_inline)
print('整行删除:', removed)
print('剩余 timeout: 次数:', s_lf.count('timeout:'))
