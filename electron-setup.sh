#!/bin/bash

# CodeFlat - Electron Desktop Setup Script v2
# Usage: Place in your existing CodeFlat Vite project root, then:
#   chmod +x electron-setup.sh && ./electron-setup.sh

set -e

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     CodeFlat → Electron Desktop Setup        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Check Node.js ──
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is required. Install from https://nodejs.org"
    exit 1
fi
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "❌ Node.js 18+ required (current: $(node -v))"
    exit 1
fi
echo "✅ Node.js $(node -v)"

# ── Check existing project ──
if [ ! -f "package.json" ]; then
    echo "❌ No package.json found. Run this in your CodeFlat project root."
    exit 1
fi
if [ ! -d "src" ]; then
    echo "❌ No src/ directory found. Run this in your CodeFlat project root."
    exit 1
fi
echo "✅ Project detected"

# ── Detect "type": "module" ──
IS_ESM=false
if grep -q '"type": *"module"' package.json 2>/dev/null; then
  IS_ESM=true
  echo "✅ ES Module project detected → will use .cjs for Electron"
fi

EXT="js"
if [ "$IS_ESM" = true ]; then EXT="cjs"; fi

echo ""

# ══════════════════════════════════════════════════
# Interactive questions
# ══════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────┐"
echo "│  Q1: Use native OS folder dialog?           │"
echo "│                                             │"
echo "│  [1] Yes - Native dialog (recommended)      │"
echo "│  [2] No  - Keep browser-style picker        │"
echo "└─────────────────────────────────────────────┘"
read -p "Choose [1/2] (default: 1): " USE_NATIVE
USE_NATIVE=${USE_NATIVE:-1}
echo ""

echo "┌─────────────────────────────────────────────┐"
echo "│  Q2: Download mirror (Electron ~110MB)      │"
echo "│                                             │"
echo "│  [1] Default (GitHub)                       │"
echo "│  [2] China mirror (npmmirror, much faster)  │"
echo "└─────────────────────────────────────────────┘"
read -p "Choose [1/2] (default: 1): " USE_MIRROR
USE_MIRROR=${USE_MIRROR:-1}
echo ""

# ── Apply mirror ──
if [ "$USE_MIRROR" = "2" ]; then
  echo "⚙️  Setting China mirrors..."
  # Project-level .npmrc (won't affect global config)
  cat > .npmrc << 'NPMRCEOF'
registry=https://registry.npmmirror.com
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/
NPMRCEOF
  echo "   ✅ .npmrc created (project-level mirrors)"
  echo ""
fi

# ══════════════════════════════════════════════════
# 1. Create Electron files
# ══════════════════════════════════════════════════
echo "📁 Creating electron/ directory..."
mkdir -p electron

cat > "electron/main.${EXT}" << MAINEOF
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');

const isDev = process.env.NODE_ENV === 'development';
let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    title: 'CodeFlat',
    icon: path.join(__dirname, '../public/icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.${EXT}'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    autoHideMenuBar: true,
  });

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(app.getAppPath(), 'dist', 'index.html'));
  }
}

ipcMain.handle('select-folder', async () => {
  const result = await dialog.showOpenDialog(mainWindow, { properties: ['openDirectory'] });
  if (result.canceled || result.filePaths.length === 0) return null;

  const folderPath = result.filePaths[0];
  const files = [];

  function walkDir(dir, relativePath) {
    relativePath = relativePath || '';
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        const relPath = relativePath ? relativePath + '/' + entry.name : entry.name;
        if (entry.isDirectory()) {
          files.push({ name: entry.name, path: relPath, type: 'directory' });
          walkDir(fullPath, relPath);
        } else if (entry.isFile()) {
          const stat = fs.statSync(fullPath);
          files.push({ name: entry.name, path: relPath, type: 'file', size: stat.size, fullPath: fullPath });
        }
      }
    } catch (e) { /* skip unreadable */ }
  }

  try {
    walkDir(folderPath);
    return { folderPath: folderPath, folderName: path.basename(folderPath), files: files };
  } catch (err) { console.error('Failed:', err); return null; }
});

ipcMain.handle('read-file', async function(_ev, fp) {
  try { return fs.readFileSync(fp, 'utf-8'); } catch(e) { return null; }
});

ipcMain.handle('save-file', async function(_ev, content, defaultName) {
  const result = await dialog.showSaveDialog(mainWindow, {
    defaultPath: defaultName || 'codeflat_output.txt',
    filters: [{ name: 'Text', extensions: ['txt'] }, { name: 'All', extensions: ['*'] }],
  });
  if (result.canceled) return false;
  try { fs.writeFileSync(result.filePath, content, 'utf-8'); return true; } catch(e) { return false; }
});

app.whenReady().then(createWindow);
app.on('window-all-closed', function() { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', function() { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
MAINEOF

cat > "electron/preload.${EXT}" << 'PREEOF'
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  selectFolder: function() { return ipcRenderer.invoke('select-folder'); },
  readFile: function(fp) { return ipcRenderer.invoke('read-file', fp); },
  saveFile: function(c, n) { return ipcRenderer.invoke('save-file', c, n); },
  isElectron: true,
});
PREEOF

echo "   ✅ electron/main.${EXT}"
echo "   ✅ electron/preload.${EXT}"

# ══════════════════════════════════════════════════
# 2. Vite config: ensure base: './'
# ══════════════════════════════════════════════════
echo ""
echo "⚙️  Checking configs..."

for VCONF in vite.config.js vite.config.ts; do
  if [ -f "$VCONF" ]; then
    if ! grep -q "base:" "$VCONF"; then
      sed -i.bak 's/plugins: \[react()\]/plugins: [react()],\n  base: ".\/"/' "$VCONF"
      rm -f "${VCONF}.bak"
      echo "   ✅ Added base: './' to $VCONF"
    else
      echo "   ✓ $VCONF already has base config"
    fi
    break
  fi
done

# ══════════════════════════════════════════════════
# 3. Ensure tailwind + postcss configs exist
# ══════════════════════════════════════════════════
if [ ! -f "tailwind.config.js" ]; then
  cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: { extend: {} },
  plugins: [],
}
EOF
  echo "   ✅ Created tailwind.config.js"
fi

if [ ! -f "postcss.config.js" ]; then
  cat > postcss.config.js << 'EOF'
export default {
  plugins: { tailwindcss: {}, autoprefixer: {} },
}
EOF
  echo "   ✅ Created postcss.config.js"
fi

# ══════════════════════════════════════════════════
# 4. Fix .gitignore
# ══════════════════════════════════════════════════
if [ -f ".gitignore" ] && grep -q "^dist$" .gitignore 2>/dev/null; then
  sed -i.bak '/^dist$/d' .gitignore
  rm -f .gitignore.bak
  echo "   ✅ Removed 'dist' from .gitignore"
fi

# ══════════════════════════════════════════════════
# 5. Update package.json
# ══════════════════════════════════════════════════
echo ""
echo "📦 Updating package.json..."

node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf-8'));
const ext = '${EXT}';

pkg.main = 'electron/main.' + ext;

pkg.scripts = pkg.scripts || {};
pkg.scripts['dev:vite'] = 'vite';
pkg.scripts['dev:electron'] = 'cross-env NODE_ENV=development electron .';
pkg.scripts['dev'] = 'concurrently \"npm run dev:vite\" \"npx wait-on http://localhost:5173 && npm run dev:electron\"';
pkg.scripts['build'] = 'vite build';
pkg.scripts['dist'] = 'npm run build && electron-builder';
pkg.scripts['dist:win'] = 'npm run build && electron-builder --win';
pkg.scripts['dist:mac'] = 'npm run build && electron-builder --mac';
pkg.scripts['dist:linux'] = 'npm run build && electron-builder --linux';

pkg.build = {
  appId: 'com.codeflat.app',
  productName: 'CodeFlat',
  asar: false,
  directories: { output: 'release' },
  files: ['**/*', '!node_modules', '!src', '!release'],
  win: { target: ['dir'], icon: 'public/icon.png', signAndEditExecutable: false },
  mac: { target: ['dmg'], icon: 'public/icon.png', category: 'public.app-category.developer-tools' },
  linux: { target: ['AppImage'], icon: 'public/icon.png', category: 'Development' },
};

fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
console.log('   ✅ package.json updated (main: electron/main.' + ext + ')');
"

# ══════════════════════════════════════════════════
# 6. Replace App.jsx if native mode
# ══════════════════════════════════════════════════
if [ "$USE_NATIVE" = "1" ]; then
  echo ""
  echo "🔄 Replacing src/App.jsx..."
  if [ -f "src/App.jsx" ]; then
    cp src/App.jsx src/App.jsx.browser-backup
    echo "   📋 Backup → src/App.jsx.browser-backup"
  fi

  cat > src/App.jsx << 'APPEOF'
import React, { useState, useCallback, useRef, useMemo, memo } from 'react';
import { FolderOpen, File, ChevronRight, ChevronDown, Copy, Download, Check, Trash2, FileText, CheckSquare, Square, Code2, Layers, AlertCircle, Filter, X, Plus, RotateCcw } from 'lucide-react';

const TEXT_EXT = new Set(['.txt','.py','.md','.json','.csv','.yaml','.yml','.ini','.cfg','.html','.js','.ts','.css','.sh','.sql','.jsx','.tsx','.vue','.xml','.env','.gitignore','.java','.c','.cpp','.h','.go','.rs','.php','.rb','.swift','.kt','.scala','.toml','.lock']);
const DEFAULT_FILTERS = ['__pycache__','.venv','venv','.git','.gitignore','.idea','.env','node_modules','.DS_Store','.vscode','dist','build','*.pyc','.cache'];
const isElectron = !!(window.electronAPI && window.electronAPI.isElectron);

const FileTreeItem = memo(({ item, level, onToggle, onToggleExpand, visiblePaths }) => {
  const isDir = item.type === 'directory';
  if (!visiblePaths.has(item.path) && level > 0) return null;
  return (
    <div>
      <div className={`flex items-center py-1.5 px-2 mx-1 my-0.5 rounded-lg cursor-pointer transition-all ${item.excluded ? 'opacity-40 hover:opacity-60' : 'hover:bg-violet-500/10'}`} style={{ paddingLeft: `${level * 16 + 8}px` }}>
        {isDir ? (<button onClick={() => onToggleExpand(item.path)} className="mr-1 p-0.5 rounded hover:bg-white/10">{item.expanded ? <ChevronDown size={14} className="text-violet-400" /> : <ChevronRight size={14} className="text-slate-500" />}</button>) : <span className="w-5" />}
        <button onClick={() => onToggle(item.path)} className="mr-2">{item.excluded ? <Square size={16} className="text-slate-500" /> : <CheckSquare size={16} className="text-emerald-400" />}</button>
        {isDir ? <FolderOpen size={14} className="mr-2 text-amber-400 flex-shrink-0" /> : <File size={14} className="mr-2 text-blue-400 flex-shrink-0" />}
        <span className="text-sm text-slate-200 truncate flex-1">{item.name}</span>
        {isDir && <span className="ml-1 text-xs text-slate-500">({item.children?.length})</span>}
      </div>
      {isDir && item.expanded && item.children?.map(child => (<FileTreeItem key={child.path} item={child} level={level + 1} onToggle={onToggle} onToggleExpand={onToggleExpand} visiblePaths={visiblePaths} />))}
    </div>
  );
});

const ProgressBar = ({ progress, label }) => (<div className="w-full"><div className="flex justify-between text-sm mb-1"><span className="text-slate-400">{label}</span><span className="text-violet-400">{Math.round(progress)}%</span></div><div className="h-2 bg-slate-800 rounded-full overflow-hidden"><div className="h-full bg-gradient-to-r from-violet-500 to-fuchsia-500 transition-all duration-200" style={{ width: `${progress}%` }} /></div></div>);
const FilterTag = memo(({ filter, onRemove, isDefault }) => (<span className={`inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs ${isDefault ? 'bg-violet-500/20 text-violet-300 border border-violet-500/30' : 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'}`}>{filter}<button onClick={() => onRemove(filter)} className="hover:text-white transition-colors"><X size={12} /></button></span>));

export default function App() {
  const [fileTree, setFileTree] = useState(null);
  const [folderName, setFolderName] = useState('');
  const [content, setContent] = useState('');
  const [isExtracting, setIsExtracting] = useState(false);
  const [progress, setProgress] = useState({ value: 0, label: '' });
  const [copied, setCopied] = useState(false);
  const [stats, setStats] = useState({ files: 0, size: 0 });
  const [activeTab, setActiveTab] = useState('tree');
  const [showPreview, setShowPreview] = useState(true);
  const [showFilterPanel, setShowFilterPanel] = useState(false);
  const [filters, setFilters] = useState(DEFAULT_FILTERS);
  const [newFilter, setNewFilter] = useState('');
  const fileInputRef = useRef(null);
  const filesMapRef = useRef(new Map());
  const contentRef = useRef('');
  const abortRef = useRef(false);

  const matchesFilter = useCallback((name, filterList) => { for (const f of filterList) { if (f.startsWith('*.')) { if (name.endsWith(f.slice(1))) return true; } else { if (name === f) return true; } } return false; }, []);

  const buildFileTreeFromList = useCallback((fileList, rootName, filterList) => {
    const root = { name: rootName, type: 'directory', path: rootName, children: [], expanded: true, excluded: false };
    const pathMap = new Map([[rootName, root]]); filesMapRef.current.clear();
    for (const f of fileList) { const fullRelPath = rootName + '/' + f.path; const parts = fullRelPath.split('/'); let curPath = '';
      for (let i = 0; i < parts.length; i++) { const parentPath = curPath; curPath = curPath ? curPath + '/' + parts[i] : parts[i];
        if (!pathMap.has(curPath)) { const pn = pathMap.get(parentPath); const pe = pn ? pn.excluded : false; const se = pe || matchesFilter(parts[i], filterList); const isFile = f.type === 'file' && i === parts.length - 1;
          const node = { name: parts[i], type: isFile ? 'file' : 'directory', path: curPath, children: isFile ? null : [], expanded: i < 2, excluded: se };
          if (isFile) filesMapRef.current.set(curPath, { fullPath: f.fullPath, size: f.size }); pathMap.set(curPath, node); if (pn) pn.children.push(node); } } } return root;
  }, [matchesFilter]);

  const buildFileTreeFromBrowser = useCallback((files, filterList) => {
    const root = { name: 'root', type: 'directory', path: '', children: [], expanded: true, excluded: false };
    const pathMap = new Map([['', root]]); filesMapRef.current.clear();
    for (const file of files) { const parts = file.webkitRelativePath.split('/'); let curPath = ''; let pe = false;
      for (let i = 0; i < parts.length; i++) { const pp = curPath; curPath = curPath ? curPath + '/' + parts[i] : parts[i]; const pn = pathMap.get(pp); if (pn && pn.excluded) pe = true;
        if (!pathMap.has(curPath)) { const isFile = i === parts.length - 1; const se = pe || matchesFilter(parts[i], filterList);
          const node = { name: parts[i], type: isFile ? 'file' : 'directory', path: curPath, children: isFile ? null : [], expanded: i < 1, excluded: se };
          if (isFile) filesMapRef.current.set(curPath, file); pathMap.set(curPath, node); if (pn) pn.children.push(node); } } }
    return root.children.length === 1 ? root.children[0] : root;
  }, [matchesFilter]);

  const applyFiltersToTree = useCallback((node, filterList, pe) => { pe = pe || false; const se = pe || matchesFilter(node.name, filterList); return { ...node, excluded: se, children: node.children ? node.children.map(c => applyFiltersToTree(c, filterList, se)) : null }; }, [matchesFilter]);

  const handleFolderSelect = useCallback(async (e) => {
    if (isElectron) { setProgress({ value: 0, label: 'Scanning folder...' }); const result = await window.electronAPI.selectFolder(); if (!result) { setProgress({ value: 0, label: '' }); return; }
      setFileTree(buildFileTreeFromList(result.files, result.folderName, filters)); setFolderName(result.folderName); setContent(''); contentRef.current = ''; setStats({ files: 0, size: 0 }); setProgress({ value: 0, label: '' });
    } else { if (e?.target?.files?.length > 0) { setProgress({ value: 0, label: 'Building file tree...' }); setTimeout(() => { setFileTree(buildFileTreeFromBrowser(e.target.files, filters)); setContent(''); contentRef.current = ''; setStats({ files: 0, size: 0 }); setProgress({ value: 0, label: '' }); }, 50); } }
  }, [buildFileTreeFromList, buildFileTreeFromBrowser, filters]);

  const toggleNode = useCallback((path) => { setFileTree(prev => { const update = (node) => { if (node.path === path) { const exc = !node.excluded; const cascade = n => ({ ...n, excluded: exc, children: n.children ? n.children.map(cascade) : null }); return cascade(node); } return node.children ? { ...node, children: node.children.map(update) } : node; }; return update(prev); }); }, []);
  const toggleExpand = useCallback((path) => { setFileTree(prev => { const update = (node) => { if (node.path === path) return { ...node, expanded: !node.expanded }; return node.children ? { ...node, children: node.children.map(update) } : node; }; return update(prev); }); }, []);

  const visiblePaths = useMemo(() => { const paths = new Set(); if (!fileTree) return paths; const traverse = (node, pv) => { if (pv) paths.add(node.path); if (node.type === 'directory' && node.expanded && node.children) node.children.forEach(c => traverse(c, pv)); }; traverse(fileTree, true); return paths; }, [fileTree]);
  const getIncludedFiles = useCallback((node, result = []) => { if (!node || node.excluded) return result; if (node.type === 'file') result.push(node); else if (node.children) node.children.forEach(c => getIncludedFiles(c, result)); return result; }, []);

  const extractContent = useCallback(async () => {
    if (!fileTree || isExtracting) return; setIsExtracting(true); abortRef.current = false;
    const files = getIncludedFiles(fileTree); const total = files.length; let result = '', count = 0, size = 0; const BATCH = 20;
    for (let i = 0; i < total; i += BATCH) { if (abortRef.current) break; const batch = files.slice(i, Math.min(i + BATCH, total));
      const promises = batch.map(async (node) => { const fileRef = filesMapRef.current.get(node.path); if (!fileRef) return null; const ext = '.' + node.name.split('.').pop().toLowerCase(); if (!TEXT_EXT.has(ext) && node.name.includes('.')) return null;
        try { let text, fileSize; if (isElectron) { text = await window.electronAPI.readFile(fileRef.fullPath); fileSize = fileRef.size; } else { text = await fileRef.text(); fileSize = fileRef.size; } if (text === null) return null; return { path: node.path, text, size: fileSize }; } catch { return null; } });
      const results = await Promise.all(promises); for (const r of results) { if (r) { result += '===== FILE: ' + r.path + ' =====\n' + r.text + '\n\n'; count++; size += r.size; } }
      setProgress({ value: ((i + batch.length) / total) * 100, label: `Processing ${i + batch.length}/${total} files...` }); await new Promise(r => setTimeout(r, 10)); }
    contentRef.current = result || 'No text files found'; setStats({ files: count, size });
    if (size > 2 * 1024 * 1024) { setShowPreview(false); setContent('[Content too large. Click "Show Content" or download.]'); } else { setShowPreview(true); setContent(contentRef.current); }
    setIsExtracting(false); setProgress({ value: 100, label: 'Done!' }); setActiveTab('result'); setTimeout(() => setProgress({ value: 0, label: '' }), 1500);
  }, [fileTree, isExtracting, getIncludedFiles]);

  const cancelExtract = () => { abortRef.current = true; };
  const copyToClipboard = async () => { await navigator.clipboard.writeText(contentRef.current); setCopied(true); setTimeout(() => setCopied(false), 2000); };
  const downloadFile = async () => { if (isElectron) { await window.electronAPI.saveFile(contentRef.current, 'codeflat_output.txt'); } else { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([contentRef.current], { type: 'text/plain' })); a.download = 'codeflat_output.txt'; a.click(); } };
  const loadFullContent = () => { setShowPreview(true); setContent(contentRef.current); };
  const addFilter = useCallback(() => { const t = newFilter.trim(); if (t && !filters.includes(t)) { const nf = [...filters, t]; setFilters(nf); setNewFilter(''); if (fileTree) setFileTree(prev => applyFiltersToTree(prev, nf)); } }, [newFilter, filters, fileTree, applyFiltersToTree]);
  const removeFilter = useCallback((filter) => { const nf = filters.filter(f => f !== filter); setFilters(nf); if (fileTree) setFileTree(prev => applyFiltersToTree(prev, nf)); }, [filters, fileTree, applyFiltersToTree]);
  const resetFilters = useCallback(() => { setFilters(DEFAULT_FILTERS); if (fileTree) setFileTree(prev => applyFiltersToTree(prev, DEFAULT_FILTERS)); }, [fileTree, applyFiltersToTree]);
  const clearAllFilters = useCallback(() => { setFilters([]); if (fileTree) { const cl = n => ({ ...n, excluded: false, children: n.children ? n.children.map(cl) : null }); setFileTree(prev => cl(prev)); } }, [fileTree]);
  const formatSize = (b) => b < 1024 ? b + ' B' : b < 1048576 ? (b/1024).toFixed(1) + ' KB' : (b/1048576).toFixed(1) + ' MB';
  const setAll = (exc) => setFileTree(p => { const u = n => ({ ...n, excluded: exc, children: n.children ? n.children.map(u) : null }); return u(p); });

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white">
      <div className="fixed inset-0 overflow-hidden pointer-events-none"><div className="absolute top-1/4 right-1/4 w-96 h-96 bg-violet-600/10 rounded-full blur-3xl" /><div className="absolute bottom-1/4 left-1/4 w-80 h-80 bg-fuchsia-600/10 rounded-full blur-3xl" /></div>
      <div className="relative z-10 max-w-7xl mx-auto p-4 sm:p-6">
        <header className="text-center mb-6">
          <div className="inline-flex items-center gap-3 mb-2"><div className="p-2.5 rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500"><Code2 size={28} /></div><h1 className="text-3xl sm:text-4xl font-bold bg-gradient-to-r from-violet-400 to-fuchsia-400 bg-clip-text text-transparent">CodeFlat</h1></div>
          <p className="text-slate-400 text-sm">Flatten your codebase for AI analysis</p>
          {isElectron && <p className="text-violet-500/50 text-xs mt-1">Desktop Edition</p>}
        </header>
        <div className="bg-slate-900/60 backdrop-blur rounded-2xl border border-slate-800 overflow-hidden">
          <div className="p-4 border-b border-slate-800">
            <div className="flex gap-2">
              {!isElectron && <input type="file" ref={fileInputRef} webkitdirectory="" directory="" multiple onChange={handleFolderSelect} className="hidden" />}
              <button onClick={() => isElectron ? handleFolderSelect() : fileInputRef.current?.click()} disabled={isExtracting} className="flex-1 py-3.5 rounded-xl font-semibold transition-all bg-gradient-to-r from-violet-600 to-fuchsia-600 hover:from-violet-500 hover:to-fuchsia-500 disabled:opacity-50 shadow-lg shadow-violet-500/20 hover:shadow-violet-500/30"><FolderOpen size={20} className="inline mr-2" /> Select Folder</button>
              <button onClick={() => setShowFilterPanel(!showFilterPanel)} className={`px-4 py-3.5 rounded-xl font-semibold transition-all border ${showFilterPanel ? 'bg-violet-500/20 border-violet-500 text-violet-300' : 'bg-slate-800 border-slate-700 hover:bg-slate-700 hover:border-slate-600'}`} title="Filter Settings"><Filter size={20} />{filters.length > 0 && <span className="ml-1.5 px-1.5 py-0.5 text-xs rounded-full bg-violet-500 text-white">{filters.length}</span>}</button>
            </div>
            {folderName && <p className="mt-2 text-xs text-slate-500 truncate">📂 {folderName}</p>}
          </div>

          {showFilterPanel && (
            <div className="p-4 border-b border-slate-800 bg-slate-800/30">
              <div className="flex items-center justify-between mb-3"><h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2"><Filter size={16} className="text-violet-400" />Auto-exclude Filters</h3>
                <div className="flex gap-2"><button onClick={resetFilters} className="px-2 py-1 text-xs rounded-md bg-slate-700 hover:bg-slate-600 text-slate-300 flex items-center gap-1"><RotateCcw size={12} /> Reset</button><button onClick={clearAllFilters} className="px-2 py-1 text-xs rounded-md bg-slate-700 hover:bg-slate-600 text-slate-300 flex items-center gap-1"><Trash2 size={12} /> Clear All</button></div></div>
              <p className="text-xs text-slate-500 mb-3">Files/folders matching these patterns will be auto-excluded. Use *.ext for extensions.</p>
              <div className="flex gap-2 mb-3"><input type="text" value={newFilter} onChange={(e) => setNewFilter(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && addFilter()} placeholder="Add filter (e.g., *.log, temp)" className="flex-1 px-3 py-2 rounded-lg bg-slate-900/50 border border-slate-700 text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-violet-500" /><button onClick={addFilter} disabled={!newFilter.trim()} className="px-3 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"><Plus size={18} /></button></div>
              <div className="flex flex-wrap gap-2 max-h-32 overflow-y-auto">{filters.length === 0 ? <span className="text-xs text-slate-500 italic">No filters active</span> : filters.map(f => <FilterTag key={f} filter={f} onRemove={removeFilter} isDefault={DEFAULT_FILTERS.includes(f)} />)}</div>
            </div>
          )}

          {progress.label && <div className="px-4 py-3 border-b border-slate-800 bg-slate-800/30"><ProgressBar progress={progress.value} label={progress.label} /></div>}

          {fileTree ? (
            <>
              <div className="flex lg:hidden border-b border-slate-800">
                <button onClick={() => setActiveTab('tree')} className={`flex-1 py-2.5 text-sm font-medium ${activeTab === 'tree' ? 'text-violet-400 border-b-2 border-violet-400' : 'text-slate-400'}`}><Layers size={14} className="inline mr-1" />Files</button>
                <button onClick={() => setActiveTab('result')} className={`flex-1 py-2.5 text-sm font-medium ${activeTab === 'result' ? 'text-violet-400 border-b-2 border-violet-400' : 'text-slate-400'}`}><FileText size={14} className="inline mr-1" />Result</button>
              </div>
              <div className="flex flex-col lg:flex-row">
                <div className={`lg:w-1/2 lg:border-r border-slate-800 ${activeTab !== 'tree' ? 'hidden lg:block' : ''}`}>
                  <div className="p-2 border-b border-slate-800 flex gap-2">
                    <button onClick={() => setAll(false)} className="px-3 py-1.5 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 flex items-center gap-1"><CheckSquare size={14} className="text-emerald-400" /> All</button>
                    <button onClick={() => setAll(true)} className="px-3 py-1.5 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 flex items-center gap-1"><Square size={14} /> None</button>
                    <button onClick={() => setFileTree(prev => applyFiltersToTree(prev, filters))} className="px-3 py-1.5 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 flex items-center gap-1"><Filter size={14} className="text-violet-400" /> Apply Filters</button>
                  </div>
                  <div className="h-[45vh] lg:h-[55vh] overflow-auto"><FileTreeItem item={fileTree} level={0} onToggle={toggleNode} onToggleExpand={toggleExpand} visiblePaths={visiblePaths} /></div>
                  <div className="p-3 border-t border-slate-800">{isExtracting ? <button onClick={cancelExtract} className="w-full py-3 rounded-xl font-semibold bg-red-600 hover:bg-red-500">Cancel</button> : <button onClick={extractContent} className="w-full py-3 rounded-xl font-semibold bg-gradient-to-r from-emerald-600 to-cyan-600 hover:from-emerald-500 hover:to-cyan-500 shadow-lg shadow-emerald-500/20"><FileText size={18} className="inline mr-2" /> Extract</button>}</div>
                </div>
                <div className={`lg:w-1/2 flex flex-col ${activeTab !== 'result' ? 'hidden lg:flex' : ''}`}>
                  <div className="p-3 border-b border-slate-800 flex items-center justify-between">
                    <div><h2 className="font-semibold">Result</h2>{stats.files > 0 && <p className="text-xs text-slate-400">{stats.files} files · {formatSize(stats.size)}</p>}</div>
                    <div className="flex gap-1.5">
                      {!showPreview && stats.size > 0 && <button onClick={loadFullContent} className="px-3 py-2 text-xs rounded-lg bg-violet-600 hover:bg-violet-500">Show Content</button>}
                      <button onClick={copyToClipboard} disabled={!stats.files} className="p-2 rounded-lg bg-slate-800 hover:bg-slate-700 disabled:opacity-40" title="Copy">{copied ? <Check size={18} className="text-emerald-400" /> : <Copy size={18} />}</button>
                      <button onClick={downloadFile} disabled={!stats.files} className="p-2 rounded-lg bg-slate-800 hover:bg-slate-700 disabled:opacity-40" title={isElectron ? "Save As..." : "Download"}><Download size={18} /></button>
                      <button onClick={() => { setContent(''); contentRef.current = ''; setStats({ files: 0, size: 0 }); }} disabled={!stats.files} className="p-2 rounded-lg bg-slate-800 hover:bg-slate-700 disabled:opacity-40" title="Clear"><Trash2 size={18} /></button>
                    </div>
                  </div>
                  {!showPreview && stats.size > 0 && <div className="mx-3 mt-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-start gap-2"><AlertCircle size={18} className="text-amber-400 flex-shrink-0 mt-0.5" /><div className="text-sm"><p className="text-amber-200 font-medium">Large content ({formatSize(stats.size)})</p><p className="text-amber-200/70 text-xs">Preview disabled. Download or click "Show Content".</p></div></div>}
                  <textarea value={content} onChange={(e) => { setContent(e.target.value); contentRef.current = e.target.value; }} placeholder="Extracted content will appear here..." className="flex-1 min-h-[45vh] lg:min-h-0 w-full p-3 bg-slate-950/50 text-slate-300 text-sm font-mono resize-none focus:outline-none" />
                </div>
              </div>
            </>
          ) : (
            <div className="py-16 text-center"><FolderOpen size={48} className="mx-auto mb-4 text-slate-600" /><p className="text-slate-400">Select a folder to get started</p><p className="text-slate-500 text-xs mt-2">{filters.length > 0 && (filters.length + ' auto-exclude filters active')}</p></div>
          )}
        </div>
      </div>
    </div>
  );
}
APPEOF

  echo "   ✅ src/App.jsx replaced (native folder dialog)"
else
  echo ""
  echo "⏭️  Keeping original src/App.jsx"
fi

# ══════════════════════════════════════════════════
# 7. Install dependencies
# ══════════════════════════════════════════════════
echo ""
echo "📦 Installing Electron dependencies..."
npm install -D electron electron-builder concurrently cross-env wait-on

# ══════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           ✅ Setup complete!                 ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Commands:"
echo ""
echo "  🔧 Dev:      npm run dev"
echo "  🧪 Test:     npm run build && npx cross-env NODE_ENV=production electron ."
echo "  📦 Package:  npm run dist:win   / dist:mac / dist:linux"
echo ""
echo "  Output:      ./release/win-unpacked/CodeFlat.exe"
echo ""
if [ "$USE_NATIVE" = "1" ]; then
  echo "  ℹ️  Original App.jsx → src/App.jsx.browser-backup"
fi
if [ "$IS_ESM" = true ]; then
  echo "  ℹ️  ES Module project: Electron files use .cjs extension"
fi
echo ""
