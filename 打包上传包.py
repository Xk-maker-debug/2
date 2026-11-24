# -*- coding: utf-8 -*-
"""
把整个 Flutter 工程打包成 zip，用于上传到 GitHub 仓库触发云构建。
排除临时探测目录、构建产物、虚拟环境。
输出：xk_mobile_app_云构建包.zip（放在工程目录的上一级）
"""
import os
import zipfile
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'xk_mobile_app_云构建包.zip')

# 排除项：临时目录、构建产物、git、缓存
EXCLUDE_DIRS = {'.tmp_probe', '.dart_tool', 'build', '.git', '.gradle', '.idea', '.vscode', '__pycache__'}
EXCLUDE_FILES = {'.DS_Store', 'pubspec.lock'}

count = 0
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(HERE):
        # 原地过滤排除目录
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            if f in EXCLUDE_FILES:
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, HERE)
            z.write(full, rel)
            count += 1

size_mb = os.path.getsize(OUT) / 1024 / 1024
print(f'打包完成：{OUT}')
print(f'文件数：{count} | 大小：{size_mb:.2f} MB')

# 校验关键文件在包内
with zipfile.ZipFile(OUT) as z:
    names = set(z.namelist())
    must = [
        'pubspec.yaml',
        '.github/workflows/build-apk.yml',
        'android/gradle/wrapper/gradle-wrapper.jar',
        'android/app/src/main/AndroidManifest.xml',
    ]
    missing = [m for m in must if m not in names]
    print('关键文件齐全：', '是' if not missing else f'否，缺 {missing}')
