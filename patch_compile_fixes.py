# -*- coding: utf-8 -*-
"""
修复 Flutter 3.24.5 编译错误（幂等）：
1. http.Client 实例方法不支持 timeout 参数 → 改用 top-level http.get/put/delete
2. Color.withValues(alpha:) 是 Flutter 3.27+ API → 改 withOpacity()
3. OpenResult.typeNoApp → ResultType.noAppToOpen
保持 UTF-8 BOM + CRLF 原样。
"""
import re
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
BOM = b'\xef\xbb\xbf'


def read(p):
    b = open(p, 'rb').read()
    has_bom = b.startswith(BOM)
    # 用 utf-8-sig 解码可正确去掉 BOM（无论有无）
    s = b.decode('utf-8-sig')
    # 记录换行风格
    nl = '\r\n' if '\r\n' in s else '\n'
    return s, has_bom, nl


def write(p, s, has_bom, nl):
    # 统一回原来的换行风格
    s = s.replace('\r\n', '\n')
    if nl == '\r\n':
        s = s.replace('\n', '\r\n')
    out = s.encode('utf-8')
    if has_bom:
        out = BOM + out
    open(p, 'wb').write(out)


# 1. api_client.dart
p = os.path.join(ROOT, 'lib', 'api', 'api_client.dart')
s, bom, nl = read(p)
before = s
s = s.replace('_http.get(', 'http.get(').replace('_http.put(', 'http.put(').replace('_http.delete(', 'http.delete(')
# 清理不再需要的 _http 字段（仅剩 dispose 用它，保留也无妨，但会 unused warning，注释掉 close）
# 保留字段和 dispose，无害
if s != before:
    write(p, s, bom, nl)
print('api_client: timeout 修复', 'OK' if s != before else '无需改')

# 2. withValues -> withOpacity（3 文件）
for rel in ['lib/screens/file_detail_screen.dart',
            'lib/screens/home_screen.dart',
            'lib/screens/upload_screen.dart']:
    p = os.path.join(ROOT, rel)
    s, bom, nl = read(p)
    s2 = re.sub(r'\.withValues\(alpha:\s*([^)]+)\)', r'.withOpacity(\1)', s)
    if s2 != s:
        write(p, s2, bom, nl)
    print(rel, 'withValues -> withOpacity:', s2.count('withOpacity'))

# 3. typeNoApp -> ResultType.noAppToOpen
p = os.path.join(ROOT, 'lib', 'screens', 'file_detail_screen.dart')
s, bom, nl = read(p)
if 'OpenResult.typeNoApp' in s:
    s = s.replace('OpenResult.typeNoApp', 'ResultType.noAppToOpen')
    write(p, s, bom, nl)
print('typeNoApp 修复: 剩余', s.count('typeNoApp'))

# 校验所有 dart 文件 BOM 完好
bad = []
for r, d, f in os.walk(os.path.join(ROOT, 'lib')):
    for n in f:
        if n.endswith('.dart'):
            fp = os.path.join(r, n)
            b = open(fp, 'rb').read()
            if not b.startswith(BOM):
                bad.append(n)
            # 检查 mojibake: BOM 被双重编码的特征 Ã¯Â»Â¿
            if 'Ã¯Â»Â¿' in b.decode('utf-8-sig', errors='ignore'):
                bad.append(n + '(mojibake!)')
print('BOM/编码异常文件:', bad if bad else '无')
