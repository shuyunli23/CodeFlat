import React, { useState, useCallback, useRef, useMemo, memo } from 'react';
import { FolderOpen, File, ChevronRight, ChevronDown, Copy, Download, Check, Trash2, FileText, CheckSquare, Square, Code2, Layers, AlertCircle, Filter, X, Plus, RotateCcw } from 'lucide-react';

const TEXT_EXT = new Set(['.txt','.py','.md','.json','.csv','.yaml','.yml','.ini','.cfg','.html','.js','.ts','.css','.sh','.sql','.jsx','.tsx','.vue','.xml','.env','.gitignore','.java','.c','.cpp','.h','.go','.rs','.php','.rb','.swift','.kt','.scala','.toml','.lock']);

// Default filter rules
const DEFAULT_FILTERS = [
  '__pycache__',
  '.venv',
  'venv',
  '.git',
  '.gitignore',
  '.idea',
  '.env',
  'node_modules',
  '.DS_Store',
  '.vscode',
  'dist',
  'build',
  '*.pyc',
  '.cache',
];

const FileTreeItem = memo(({ item, level, onToggle, onToggleExpand, visiblePaths }) => {
  const isDir = item.type === 'directory';
  const isVisible = visiblePaths.has(item.path);
  if (!isVisible && level > 0) return null;
  
  return (
    <div>
      <div 
        className={`flex items-center py-1.5 px-2 mx-1 my-0.5 rounded-lg cursor-pointer transition-all
          ${item.excluded ? 'opacity-40 hover:opacity-60' : 'hover:bg-violet-500/10'}`}
        style={{ paddingLeft: `${level * 16 + 8}px` }}
      >
        {isDir ? (
          <button onClick={() => onToggleExpand(item.path)} className="mr-1 p-0.5 rounded hover:bg-white/10">
            {item.expanded ? <ChevronDown size={14} className="text-violet-400" /> : <ChevronRight size={14} className="text-slate-500" />}
          </button>
        ) : <span className="w-5" />}
        
        <button onClick={() => onToggle(item.path)} className="mr-2">
          {item.excluded ? <Square size={16} className="text-slate-500" /> : <CheckSquare size={16} className="text-emerald-400" />}
        </button>
        
        {isDir 
          ? <FolderOpen size={14} className="mr-2 text-amber-400 flex-shrink-0" />
          : <File size={14} className="mr-2 text-blue-400 flex-shrink-0" />
        }
        <span className="text-sm text-slate-200 truncate flex-1">{item.name}</span>
        {isDir && <span className="ml-1 text-xs text-slate-500">({item.children?.length})</span>}
      </div>
      {isDir && item.expanded && item.children?.map(child => (
        <FileTreeItem key={child.path} item={child} level={level + 1} onToggle={onToggle} onToggleExpand={onToggleExpand} visiblePaths={visiblePaths} />
      ))}
    </div>
  );
});

const ProgressBar = ({ progress, label }) => (
  <div className="w-full">
    <div className="flex justify-between text-sm mb-1">
      <span className="text-slate-400">{label}</span>
      <span className="text-violet-400">{Math.round(progress)}%</span>
    </div>
    <div className="h-2 bg-slate-800 rounded-full overflow-hidden">
      <div className="h-full bg-gradient-to-r from-violet-500 to-fuchsia-500 transition-all duration-200" style={{ width: `${progress}%` }} />
    </div>
  </div>
);

// Filter rule label component
const FilterTag = memo(({ filter, onRemove, isDefault }) => (
  <span className={`inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs ${
    isDefault ? 'bg-violet-500/20 text-violet-300 border border-violet-500/30' : 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
  }`}>
    {filter}
    <button onClick={() => onRemove(filter)} className="hover:text-white transition-colors">
      <X size={12} />
    </button>
  </span>
));

export default function App() {
  const [fileTree, setFileTree] = useState(null);
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

  // Check if files/folders match filter rules
  const matchesFilter = useCallback((name, filterList) => {
    for (const filter of filterList) {
      // Supports wildcards *.ext
      if (filter.startsWith('*.')) {
        const ext = filter.slice(1);
        if (name.endsWith(ext)) return true;
      } else {
        // Exact file name match
        if (name === filter) return true;
      }
    }
    return false;
  }, []);

  const buildFileTree = useCallback((files, filterList) => {
    const root = { name: 'root', type: 'directory', path: '', children: [], expanded: true, excluded: false };
    const pathMap = new Map([['', root]]);
    filesMapRef.current.clear();
    
    for (const file of files) {
      const parts = file.webkitRelativePath.split('/');
      let curPath = '';
      let parentExcluded = false;
      
      for (let i = 0; i < parts.length; i++) {
        const parentPath = curPath;
        curPath = curPath ? `${curPath}/${parts[i]}` : parts[i];
        
        // Check if the parent node is filtered
        const parentNode = pathMap.get(parentPath);
        if (parentNode?.excluded) {
          parentExcluded = true;
        }
        
        if (!pathMap.has(curPath)) {
          const isFile = i === parts.length - 1;
          const shouldExclude = parentExcluded || matchesFilter(parts[i], filterList);
          
          const node = { 
            name: parts[i], 
            type: isFile ? 'file' : 'directory', 
            path: curPath, 
            children: isFile ? null : [], 
            expanded: i < 1, 
            excluded: shouldExclude 
          };
          
          if (isFile) filesMapRef.current.set(curPath, file);
          pathMap.set(curPath, node);
          pathMap.get(parentPath)?.children.push(node);
        }
      }
    }
    return root.children.length === 1 ? root.children[0] : root;
  }, [matchesFilter]);

  // Reapply filtering rules to existing file tree
  const applyFiltersToTree = useCallback((node, filterList, parentExcluded = false) => {
    const shouldExclude = parentExcluded || matchesFilter(node.name, filterList);
    return {
      ...node,
      excluded: shouldExclude,
      children: node.children?.map(child => applyFiltersToTree(child, filterList, shouldExclude))
    };
  }, [matchesFilter]);

  const handleFolderSelect = useCallback((e) => {
    if (e.target.files.length > 0) {
      setProgress({ value: 0, label: 'Building file tree...' });
      setTimeout(() => {
        const tree = buildFileTree(e.target.files, filters);
        setFileTree(tree);
        setContent('');
        contentRef.current = '';
        setStats({ files: 0, size: 0 });
        setProgress({ value: 0, label: '' });
      }, 50);
    }
  }, [buildFileTree, filters]);

  const toggleNode = useCallback((path) => {
    setFileTree(prev => {
      const update = (node) => {
        if (node.path === path) {
          const exc = !node.excluded;
          const cascade = (n) => ({ ...n, excluded: exc, children: n.children?.map(cascade) });
          return cascade(node);
        }
        return node.children ? { ...node, children: node.children.map(update) } : node;
      };
      return update(prev);
    });
  }, []);

  const toggleExpand = useCallback((path) => {
    setFileTree(prev => {
      const update = (node) => {
        if (node.path === path) return { ...node, expanded: !node.expanded };
        return node.children ? { ...node, children: node.children.map(update) } : node;
      };
      return update(prev);
    });
  }, []);

  const visiblePaths = useMemo(() => {
    const paths = new Set();
    if (!fileTree) return paths;
    const traverse = (node, parentVisible) => {
      if (parentVisible) paths.add(node.path);
      if (node.type === 'directory' && node.expanded) {
        node.children?.forEach(c => traverse(c, parentVisible));
      }
    };
    traverse(fileTree, true);
    return paths;
  }, [fileTree]);

  const getIncludedFiles = useCallback((node, result = []) => {
    if (!node || node.excluded) return result;
    if (node.type === 'file') result.push(node);
    else node.children?.forEach(c => getIncludedFiles(c, result));
    return result;
  }, []);

  const extractContent = useCallback(async () => {
    if (!fileTree || isExtracting) return;
    setIsExtracting(true);
    abortRef.current = false;
    
    const files = getIncludedFiles(fileTree);
    const total = files.length;
    let result = '', count = 0, size = 0;
    const BATCH = 20;

    for (let i = 0; i < total; i += BATCH) {
      if (abortRef.current) break;
      
      const batch = files.slice(i, Math.min(i + BATCH, total));
      const promises = batch.map(async (node) => {
        const file = filesMapRef.current.get(node.path);
        if (!file) return null;
        const ext = '.' + file.name.split('.').pop().toLowerCase();
        if (!TEXT_EXT.has(ext) && file.name.includes('.')) return null;
        try {
          const text = await file.text();
          return { path: node.path, text, size: file.size };
        } catch { return null; }
      });

      const results = await Promise.all(promises);
      for (const r of results) {
        if (r) {
          result += `===== FILE: ${r.path} =====\n${r.text}\n\n`;
          count++; size += r.size;
        }
      }

      setProgress({ value: ((i + batch.length) / total) * 100, label: `Processing ${i + batch.length}/${total} files...` });
      await new Promise(r => setTimeout(r, 10));
    }

    contentRef.current = result || 'No text files found';
    setStats({ files: count, size });
    
    if (size > 2 * 1024 * 1024) {
      setShowPreview(false);
      setContent('[Content too large to preview. Click "Show Content" or download directly.]');
    } else {
      setShowPreview(true);
      setContent(contentRef.current);
    }
    
    setIsExtracting(false);
    setProgress({ value: 100, label: 'Done!' });
    setActiveTab('result');
    setTimeout(() => setProgress({ value: 0, label: '' }), 1500);
  }, [fileTree, isExtracting, getIncludedFiles]);

  const cancelExtract = () => { abortRef.current = true; };

  const copyToClipboard = async () => {
    await navigator.clipboard.writeText(contentRef.current);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const downloadFile = () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([contentRef.current], { type: 'text/plain' }));
    a.download = 'codeflat_output.txt';
    a.click();
  };

  const loadFullContent = () => {
    setShowPreview(true);
    setContent(contentRef.current);
  };

  // Filter rule management
  const addFilter = useCallback(() => {
    const trimmed = newFilter.trim();
    if (trimmed && !filters.includes(trimmed)) {
      const newFilters = [...filters, trimmed];
      setFilters(newFilters);
      setNewFilter('');
      // If a file tree already exists, reapply filtering
      if (fileTree) {
        setFileTree(prev => applyFiltersToTree(prev, newFilters));
      }
    }
  }, [newFilter, filters, fileTree, applyFiltersToTree]);

  const removeFilter = useCallback((filter) => {
    const newFilters = filters.filter(f => f !== filter);
    setFilters(newFilters);
    // If a file tree already exists, reapply filtering
    if (fileTree) {
      setFileTree(prev => applyFiltersToTree(prev, newFilters));
    }
  }, [filters, fileTree, applyFiltersToTree]);

  const resetFilters = useCallback(() => {
    setFilters(DEFAULT_FILTERS);
    if (fileTree) {
      setFileTree(prev => applyFiltersToTree(prev, DEFAULT_FILTERS));
    }
  }, [fileTree, applyFiltersToTree]);

  const clearAllFilters = useCallback(() => {
    setFilters([]);
    if (fileTree) {
      // Cancel all automatic filtering and set all to Not Excluded
      const clearExclusions = (node) => ({
        ...node,
        excluded: false,
        children: node.children?.map(clearExclusions)
      });
      setFileTree(prev => clearExclusions(prev));
    }
  }, [fileTree]);

  const formatSize = (b) => b < 1024 ? b + ' B' : b < 1048576 ? (b/1024).toFixed(1) + ' KB' : (b/1048576).toFixed(1) + ' MB';
  const setAll = (exc) => setFileTree(p => { const u = n => ({ ...n, excluded: exc, children: n.children?.map(u) }); return u(p); });

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white">
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 right-1/4 w-96 h-96 bg-violet-600/10 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 left-1/4 w-80 h-80 bg-fuchsia-600/10 rounded-full blur-3xl" />
      </div>

      <div className="relative z-10 max-w-7xl mx-auto p-4 sm:p-6">
        <header className="text-center mb-6">
          <div className="inline-flex items-center gap-3 mb-2">
            <div className="p-2.5 rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500">
              <Code2 size={28} />
            </div>
            <h1 className="text-3xl sm:text-4xl font-bold bg-gradient-to-r from-violet-400 to-fuchsia-400 bg-clip-text text-transparent">
              CodeFlat
            </h1>
          </div>
          <p className="text-slate-400 text-sm">Flatten your codebase for AI analysis</p>
        </header>

        <div className="bg-slate-900/60 backdrop-blur rounded-2xl border border-slate-800 overflow-hidden">
          <div className="p-4 border-b border-slate-800">
            <div className="flex gap-2">
              <input type="file" ref={fileInputRef} webkitdirectory="" directory="" multiple onChange={handleFolderSelect} className="hidden" />
              <button
                onClick={() => fileInputRef.current?.click()}
                disabled={isExtracting}
                className="flex-1 py-3.5 rounded-xl font-semibold transition-all bg-gradient-to-r from-violet-600 to-fuchsia-600 hover:from-violet-500 hover:to-fuchsia-500 disabled:opacity-50 shadow-lg shadow-violet-500/20 hover:shadow-violet-500/30"
              >
                <FolderOpen size={20} className="inline mr-2" /> Select Folder
              </button>
              <button
                onClick={() => setShowFilterPanel(!showFilterPanel)}
                className={`px-4 py-3.5 rounded-xl font-semibold transition-all border ${
                  showFilterPanel 
                    ? 'bg-violet-500/20 border-violet-500 text-violet-300' 
                    : 'bg-slate-800 border-slate-700 hover:bg-slate-700 hover:border-slate-600'
                }`}
                title="Filter Settings"
              >
                <Filter size={20} />
                {filters.length > 0 && (
                  <span className="ml-1.5 px-1.5 py-0.5 text-xs rounded-full bg-violet-500 text-white">
                    {filters.length}
                  </span>
                )}
              </button>
            </div>
          </div>

          {/* Filter rules panel */}
          {showFilterPanel && (
            <div className="p-4 border-b border-slate-800 bg-slate-800/30">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
                  <Filter size={16} className="text-violet-400" />
                  Auto-exclude Filters
                </h3>
                <div className="flex gap-2">
                  <button
                    onClick={resetFilters}
                    className="px-2 py-1 text-xs rounded-md bg-slate-700 hover:bg-slate-600 text-slate-300 flex items-center gap-1"
                    title="Reset to defaults"
                  >
                    <RotateCcw size={12} /> Reset
                  </button>
                  <button
                    onClick={clearAllFilters}
                    className="px-2 py-1 text-xs rounded-md bg-slate-700 hover:bg-slate-600 text-slate-300 flex items-center gap-1"
                    title="Clear all filters"
                  >
                    <Trash2 size={12} /> Clear All
                  </button>
                </div>
              </div>
              
              <p className="text-xs text-slate-500 mb-3">
                Files/folders matching these patterns will be auto-excluded. Use *.ext for extensions.
              </p>
              
              {/* Add new filter rule */}
              <div className="flex gap-2 mb-3">
                <input
                  type="text"
                  value={newFilter}
                  onChange={(e) => setNewFilter(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && addFilter()}
                  placeholder="Add filter (e.g., *.log, temp, .cache)"
                  className="flex-1 px-3 py-2 rounded-lg bg-slate-900/50 border border-slate-700 text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-violet-500"
                />
                <button
                  onClick={addFilter}
                  disabled={!newFilter.trim()}
                  className="px-3 py-2 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                >
                  <Plus size={18} />
                </button>
              </div>
              
              {/* filter rule label */}
              <div className="flex flex-wrap gap-2 max-h-32 overflow-y-auto">
                {filters.length === 0 ? (
                  <span className="text-xs text-slate-500 italic">No filters active</span>
                ) : (
                  filters.map(filter => (
                    <FilterTag 
                      key={filter} 
                      filter={filter} 
                      onRemove={removeFilter}
                      isDefault={DEFAULT_FILTERS.includes(filter)}
                    />
                  ))
                )}
              </div>
            </div>
          )}

          {progress.label && (
            <div className="px-4 py-3 border-b border-slate-800 bg-slate-800/30">
              <ProgressBar progress={progress.value} label={progress.label} />
            </div>
          )}

          {fileTree ? (
            <>
              <div className="flex lg:hidden border-b border-slate-800">
                <button onClick={() => setActiveTab('tree')} className={`flex-1 py-2.5 text-sm font-medium ${activeTab === 'tree' ? 'text-violet-400 border-b-2 border-violet-400' : 'text-slate-400'}`}>
                  <Layers size={14} className="inline mr-1" />Files
                </button>
                <button onClick={() => setActiveTab('result')} className={`flex-1 py-2.5 text-sm font-medium ${activeTab === 'result' ? 'text-violet-400 border-b-2 border-violet-400' : 'text-slate-400'}`}>
                  <FileText size={14} className="inline mr-1" />Result
                </button>
              </div>

              <div className="flex flex-col lg:flex-row">
                <div className={`lg:w-1/2 lg:border-r border-slate-800 ${activeTab !== 'tree' ? 'hidden lg:block' : ''}`}>
                  <div className="p-2 border-b border-slate-800 flex gap-2">
                    <button onClick={() => setAll(false)} className="px-3 py-1.5 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 flex items-center gap-1">
                      <CheckSquare size={14} className="text-emerald-400" /> All
                    </button>
                    <button onClick={() => setAll(true)} className="px-3 py-1.5 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 flex items-center gap-1">
                      <Square size={14} /> None
                    </button>
                    <button 
                      onClick={() => setFileTree(prev => applyFiltersToTree(prev, filters))} 
                      className="px-3 py-1.5 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 flex items-center gap-1"
                      title="Re-apply filter rules"
                    >
                      <Filter size={14} className="text-violet-400" /> Apply Filters
                    </button>
                  </div>
                  
                  <div className="h-[45vh] lg:h-[55vh] overflow-auto">
                    <FileTreeItem item={fileTree} level={0} onToggle={toggleNode} onToggleExpand={toggleExpand} visiblePaths={visiblePaths} />
                  </div>

                  <div className="p-3 border-t border-slate-800">
                    {isExtracting ? (
                      <button onClick={cancelExtract} className="w-full py-3 rounded-xl font-semibold bg-red-600 hover:bg-red-500">
                        Cancel
                      </button>
                    ) : (
                      <button onClick={extractContent} className="w-full py-3 rounded-xl font-semibold bg-gradient-to-r from-emerald-600 to-cyan-600 hover:from-emerald-500 hover:to-cyan-500 shadow-lg shadow-emerald-500/20">
                        <FileText size={18} className="inline mr-2" /> Extract
                      </button>
                    )}
                  </div>
                </div>

                <div className={`lg:w-1/2 flex flex-col ${activeTab !== 'result' ? 'hidden lg:flex' : ''}`}>
                  <div className="p-3 border-b border-slate-800 flex items-center justify-between">
                    <div>
                      <h2 className="font-semibold">Result</h2>
                      {stats.files > 0 && <p className="text-xs text-slate-400">{stats.files} files · {formatSize(stats.size)}</p>}
                    </div>
                    <div className="flex gap-1.5">
                      {!showPreview && stats.size > 0 && (
                        <button onClick={loadFullContent} className="px-3 py-2 text-xs rounded-lg bg-violet-600 hover:bg-violet-500">
                          Show Content
                        </button>
                      )}
                      <button onClick={copyToClipboard} disabled={!stats.files} className="p-2 rounded-lg bg-slate-800 hover:bg-slate-700 disabled:opacity-40" title="Copy">
                        {copied ? <Check size={18} className="text-emerald-400" /> : <Copy size={18} />}
                      </button>
                      <button onClick={downloadFile} disabled={!stats.files} className="p-2 rounded-lg bg-slate-800 hover:bg-slate-700 disabled:opacity-40" title="Download">
                        <Download size={18} />
                      </button>
                      <button onClick={() => { setContent(''); contentRef.current = ''; setStats({ files: 0, size: 0 }); }} disabled={!stats.files} className="p-2 rounded-lg bg-slate-800 hover:bg-slate-700 disabled:opacity-40" title="Clear">
                        <Trash2 size={18} />
                      </button>
                    </div>
                  </div>
                  
                  {!showPreview && stats.size > 0 && (
                    <div className="mx-3 mt-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-start gap-2">
                      <AlertCircle size={18} className="text-amber-400 flex-shrink-0 mt-0.5" />
                      <div className="text-sm">
                        <p className="text-amber-200 font-medium">Large content ({formatSize(stats.size)})</p>
                        <p className="text-amber-200/70 text-xs">Preview disabled. Download or click "Show Content".</p>
                      </div>
                    </div>
                  )}
                  
                  <textarea
                    value={content}
                    onChange={(e) => { setContent(e.target.value); contentRef.current = e.target.value; }}
                    placeholder="Extracted content will appear here..."
                    className="flex-1 min-h-[45vh] lg:min-h-0 w-full p-3 bg-slate-950/50 text-slate-300 text-sm font-mono resize-none focus:outline-none"
                  />
                </div>
              </div>
            </>
          ) : (
            <div className="py-16 text-center">
              <FolderOpen size={48} className="mx-auto mb-4 text-slate-600" />
              <p className="text-slate-400">Select a folder to get started</p>
              <p className="text-slate-500 text-xs mt-2">
                {filters.length > 0 && `${filters.length} auto-exclude filters active`}
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}