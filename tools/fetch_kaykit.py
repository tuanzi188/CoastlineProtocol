import json
import struct
import sys
import urllib.request

REPO = 'KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0'
TREE = 'addons/kaykit_character_pack_adventures/Characters/gltf'
TEXTURES = 'addons/kaykit_character_pack_adventures/Textures'
BASE = 'https://api.github.com/repos/%s/git/blobs/' % REPO


def get(url, raw=False):
    req = urllib.request.Request(url, headers={
        'User-Agent': 'qoder-asset-fetch',
        'Accept': 'application/vnd.github.raw' if raw else 'application/vnd.github+json',
    })
    with urllib.request.urlopen(req, timeout=180) as response:
        return response.read()


def listing(folder):
    url = 'https://api.github.com/repos/%s/contents/%s' % (REPO, folder)
    return json.loads(get(url).decode())


def blob_sha(name):
    folders = [TREE, TEXTURES]
    for folder in folders:
        for entry in listing(folder):
            if entry['name'] == name:
                return entry['sha'], entry['size']
    raise SystemExit('missing %s' % name)


def describe(data, name):
    length = struct.unpack('<I', data[8:12])[0]
    chunk_len = struct.unpack('<I', data[12:16])[0]
    json_chunk = json.loads(data[20:20 + chunk_len].decode())
    meshes = [(m.get('name') or 'mesh%d' % i, len(m.get('primitives', []))) for i, m in enumerate(json_chunk.get('meshes', []))]
    skins = [s.get('name') or 'skin%d' % i for i, s in enumerate(json_chunk.get('skins', []))]
    animations = json_chunk.get('animations', [])
    print('%s: %d bytes' % (name, len(data)))
    print('  meshes     :', meshes[:8])
    print('  skins      :', skins)
    print('  nodes      :', len(json_chunk.get('nodes', [])))
    print('  animations :', len(animations))
    for anim in animations:
        print('    -', anim.get('name') or '(unnamed)', 'channels', len(anim.get('channels', [])))


def main():
    wanted = sys.argv[1:] or ['Knight.glb']
    out_dir = 'D:/游戏空间/CoastlineProtocol/assets/characters/'
    import os
    os.makedirs(out_dir, exist_ok=True)
    for name in wanted:
        sha, size = blob_sha(name)
        data = get(BASE + sha, raw=True)
        print('fetched %s (%d bytes, expected %d)' % (name, len(data), size))
        if len(data) != size:
            raise SystemExit('truncated download for %s' % name)
        with open(out_dir + name, 'wb') as handle:
            handle.write(data)
        if name.endswith(".glb"):
            describe(data, name)


main()
