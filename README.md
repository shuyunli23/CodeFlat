# CodeFlat

<p align="center">
  <img src="https://img.shields.io/badge/React-18.x-61dafb?logo=react" alt="React">
  <img src="https://img.shields.io/badge/Vite-5.x-646cff?logo=vite" alt="Vite">
  <img src="https://img.shields.io/badge/TailwindCSS-3.x-38bdf8?logo=tailwindcss" alt="Tailwind">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

**CodeFlat** is a browser-based tool that flattens your codebase into a single text file, perfect for AI analysis, code reviews, or documentation purposes. It runs entirely in your browser with no server-side processing—your code never leaves your machine.

## ✨ Features

- **🔒 Privacy First** - All processing happens locally in your browser
- **🎯 Smart Auto-Filtering** - Automatically excludes common non-essential files (`node_modules`, `__pycache__`, `.git`, etc.)
- **📁 Interactive File Tree** - Visual selection with expand/collapse functionality
- **⚡ Batch Processing** - Efficiently handles large codebases
- **📋 Multiple Export Options** - Copy to clipboard or download as file
- **🎨 Modern UI** - Clean, responsive dark-themed interface
- **🔧 Customizable Filters** - Add or remove filter rules as needed

## 📋 Prerequisites

Before installation, ensure you have the following installed:

- **Node.js** (v18.0.0 or higher)
- **npm** (v9.0.0 or higher) - comes with Node.js

### Verify Installation

```bash
node --version   # Should output v18.x.x or higher
npm --version    # Should output 9.x.x or higher
```

---

## 🚀 Deployment

### Option 1: One-Click Setup (Recommended)

#### Linux / macOS

```bash
# Download and run the setup script
chmod +x setup.sh
./setup.sh

# Start the development server
cd codeflat
npm run dev
```

#### Windows (PowerShell)

```powershell
# Run the setup script using Git Bash or WSL
bash setup.sh

# Or manually execute each step (see Option 2)
```

---

### Option 2: Manual Installation

#### Step 1: Create Vite Project

**Linux / macOS:**
```bash
npm create vite@latest codeflat -- --template react
cd codeflat
```

**Windows (Command Prompt):**
```cmd
npm create vite@latest codeflat -- --template react
cd codeflat
```

**Windows (PowerShell):**
```powershell
npm create vite@latest codeflat -- --template react
Set-Location codeflat
```

#### Step 2: Install Dependencies

```bash
npm install
npm install lucide-react
npm install -D tailwindcss@3 postcss autoprefixer
npx tailwindcss init -p
```

#### Step 3: Configure Tailwind CSS

Replace the contents of `tailwind.config.js`:

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

#### Step 4: Configure CSS

Replace the contents of `src/index.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

#### Step 5: Add Application Code

Replace `src/App.jsx` with the provided `App.jsx` file.

#### Step 6: Start Development Server

```bash
npm run dev
```

Open your browser and navigate to `http://localhost:5173`

---

## 🖥️ Platform-Specific Notes

### Windows

**Using Command Prompt:**
```cmd
cd codeflat
npm run dev
```

**Using PowerShell:**
```powershell
Set-Location codeflat
npm run dev
```

**Using Git Bash (Recommended):**
```bash
cd codeflat
npm run dev
```

> **Note:** If you encounter permission issues, run your terminal as Administrator.

### macOS

```bash
cd codeflat
npm run dev
```

> **Note:** If you get permission errors with npm, you may need to fix npm permissions:
> ```bash
> sudo chown -R $(whoami) ~/.npm
> ```

### Linux (Ubuntu/Debian)

```bash
cd codeflat
npm run dev
```

> **Note:** Install Node.js via NodeSource if not available:
> ```bash
> curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
> sudo apt-get install -y nodejs
> ```

### Linux (Fedora/RHEL)

```bash
cd codeflat
npm run dev
```

> **Note:** Install Node.js via dnf:
> ```bash
> sudo dnf install nodejs npm
> ```

---

## 🏗️ Production Build

To create an optimized production build:

```bash
npm run build
```

The output will be in the `dist/` directory. You can serve it with any static file server:

```bash
# Using npm serve
npm install -g serve
serve -s dist

# Using Python
cd dist && python -m http.server 8080

# Using Node.js http-server
npm install -g http-server
http-server dist
```

---

## 🐳 Docker Deployment (Optional)

Create a `Dockerfile` in your project root:

```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

Build and run:

```bash
docker build -t codeflat .
docker run -p 8080:80 codeflat
```

---

## 📖 Usage Guide

1. **Select Folder** - Click the "Select Folder" button and choose your project directory
2. **Configure Filters** - Click the filter icon to manage auto-exclude rules
3. **Select Files** - Use checkboxes to include/exclude specific files or folders
4. **Extract** - Click "Extract" to generate the flattened output
5. **Export** - Copy to clipboard or download as a text file

### Default Filter Rules

The following patterns are excluded by default:

| Pattern | Description |
|---------|-------------|
| `__pycache__` | Python bytecode cache |
| `.venv` / `venv` | Python virtual environments |
| `.git` | Git repository data |
| `.gitignore` | Git ignore file |
| `.idea` | JetBrains IDE settings |
| `.env` | Environment variables |
| `node_modules` | Node.js dependencies |
| `.DS_Store` | macOS folder metadata |
| `.vscode` | VS Code settings |
| `dist` / `build` | Build output directories |
| `*.pyc` | Compiled Python files |
| `.cache` | Cache directories |

### Custom Filters

- Click the **Filter** button to open the filter panel
- Add new patterns in the input field (e.g., `*.log`, `temp`, `.myconfig`)
- Use `*.ext` syntax to match file extensions
- Click the **×** on any tag to remove a filter
- Use **Reset** to restore default filters
- Use **Clear All** to disable all auto-filtering

---

## 🔧 Troubleshooting

### Common Issues

**"npm: command not found"**
- Ensure Node.js is installed and added to your PATH
- Restart your terminal after installation

**"EACCES: permission denied"**
- On Linux/macOS: Fix npm permissions or use nvm
- On Windows: Run terminal as Administrator

**Port 5173 already in use**
```bash
# Use a different port
npm run dev -- --port 3000
```

**Folder selection not working**
- Ensure you're using a modern browser (Chrome, Firefox, Edge)
- The `webkitdirectory` attribute may not work in all browsers

---

## 📄 License

This project is licensed under the MIT License.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request