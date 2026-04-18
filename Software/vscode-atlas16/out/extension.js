"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
const fs = __importStar(require("fs"));
const child_process_1 = require("child_process");
const DIAG = vscode.languages.createDiagnosticCollection('atlas16');
function activate(ctx) {
    ctx.subscriptions.push(DIAG);
    // Diagnostics bei Speichern
    ctx.subscriptions.push(vscode.workspace.onDidSaveTextDocument(doc => {
        if (doc.languageId === 'hack-asm')
            validateAsm(doc);
        if (doc.languageId === 'jack')
            validateJack(doc);
    }));
    // Befehle
    ctx.subscriptions.push(vscode.commands.registerCommand('atlas16.compile', () => runBuild(false)), vscode.commands.registerCommand('atlas16.compileAndLoad', () => runBuild(true)));
}
function deactivate() { DIAG.clear(); }
// ── JAR-Pfad ermitteln ────────────────────────────────────────────────────────
function jarPath() {
    const cfg = vscode.workspace.getConfiguration('atlas16').get('jarPath');
    if (cfg && cfg.length > 0 && fs.existsSync(cfg))
        return cfg;
    // Workspace nach atlas16.jar durchsuchen
    const folders = vscode.workspace.workspaceFolders;
    if (!folders)
        return null;
    for (const folder of folders) {
        const candidate = path.join(folder.uri.fsPath, 'Software', 'atlas16', 'target', 'atlas16.jar');
        if (fs.existsSync(candidate))
            return candidate;
    }
    return null;
}
// ── Validierung / Diagnostics ─────────────────────────────────────────────────
function validateAsm(doc) {
    const jar = jarPath();
    if (!jar) {
        DIAG.set(doc.uri, []);
        return;
    }
    runJar(jar, ['asm', doc.fileName, '-o', '/dev/null'], (code, stdout, stderr) => {
        DIAG.set(doc.uri, parseAsmErrors(stderr, doc));
    });
}
function validateJack(doc) {
    const jar = jarPath();
    if (!jar) {
        DIAG.set(doc.uri, []);
        return;
    }
    runJar(jar, ['jack', doc.fileName], (code, _out, stderr) => {
        DIAG.set(doc.uri, parseJackErrors(stderr, doc));
    });
}
function parseAsmErrors(stderr, doc) {
    const diags = [];
    // Format: "Zeile 42: Unbekannter comp-Wert 'XY'."
    const re = /Zeile\s+(\d+):\s+(.+)/g;
    let m;
    while ((m = re.exec(stderr)) !== null) {
        const line = Math.max(0, parseInt(m[1]) - 1);
        const range = doc.lineAt(Math.min(line, doc.lineCount - 1)).range;
        diags.push(new vscode.Diagnostic(range, m[2], vscode.DiagnosticSeverity.Error));
    }
    // Fallback: beliebige Fehler-Zeile
    if (diags.length === 0 && stderr.includes('Fehler:')) {
        const msg = stderr.replace(/^Fehler:\s*/m, '').trim();
        if (msg)
            diags.push(new vscode.Diagnostic(new vscode.Range(0, 0, 0, 0), msg, vscode.DiagnosticSeverity.Error));
    }
    return diags;
}
function parseJackErrors(stderr, doc) {
    const diags = [];
    if (stderr.includes('Fehler:')) {
        const msg = stderr.replace(/^Fehler:\s*/m, '').trim();
        if (msg)
            diags.push(new vscode.Diagnostic(new vscode.Range(0, 0, 0, 0), msg, vscode.DiagnosticSeverity.Error));
    }
    return diags;
}
// ── Build & Upload ────────────────────────────────────────────────────────────
async function runBuild(withLoad) {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage('Kein aktiver Editor.');
        return;
    }
    const doc = editor.document;
    const lang = doc.languageId;
    if (lang !== 'hack-asm' && lang !== 'jack') {
        vscode.window.showErrorMessage('Aktive Datei ist kein .asm oder .jack.');
        return;
    }
    const jar = jarPath();
    if (!jar) {
        vscode.window.showErrorMessage('atlas16.jar nicht gefunden. Bitte atlas16.jarPath in den Einstellungen konfigurieren.');
        return;
    }
    await doc.save();
    const cfg = vscode.workspace.getConfiguration('atlas16');
    const ip = cfg.get('deviceIp') ?? '';
    const user = cfg.get('sshUser') ?? 'root';
    const out = vscode.window.createOutputChannel('Atlas 16');
    out.show(true);
    out.appendLine(`── Atlas 16 Build ──────────────────────────────`);
    return new Promise(resolve => {
        // Jack: ein einziger `build`-Aufruf macht alles
        if (lang === 'jack') {
            const args = ['build', doc.fileName, ...(withLoad && ip ? ['--ip', ip, '--user', user] : [])];
            out.appendLine(`java -jar atlas16.jar ${args.join(' ')}`);
            runJar(jar, args, (code, stdout, stderr) => {
                if (stdout)
                    out.append(stdout);
                if (stderr)
                    out.append(stderr);
                finalize(code, stderr, doc, lang, out);
                resolve();
            });
            return;
        }
        // Hack-ASM: erst asm, dann optional load
        const hackFile = doc.fileName.replace(/\.asm$/, '.hack');
        const asmArgs = ['asm', doc.fileName, '-o', hackFile];
        out.appendLine(`java -jar atlas16.jar ${asmArgs.join(' ')}`);
        runJar(jar, asmArgs, (code, stdout, stderr) => {
            if (stdout)
                out.append(stdout);
            if (stderr)
                out.append(stderr);
            if (code !== 0) {
                finalize(code, stderr, doc, lang, out);
                resolve();
                return;
            }
            if (!withLoad || !ip) {
                finalize(0, '', doc, lang, out);
                resolve();
                return;
            }
            const loadArgs = ['load', hackFile, '--ip', ip, '--user', user];
            out.appendLine(`java -jar atlas16.jar ${loadArgs.join(' ')}`);
            runJar(jar, loadArgs, (code2, stdout2, stderr2) => {
                if (stdout2)
                    out.append(stdout2);
                if (stderr2)
                    out.append(stderr2);
                finalize(code2, stderr2, doc, lang, out);
                resolve();
            });
        });
    });
}
function finalize(code, stderr, doc, lang, out) {
    if (code === 0) {
        out.appendLine('✓ Erfolgreich.');
        vscode.window.setStatusBarMessage('Atlas 16: ✓ Fertig', 4000);
        DIAG.set(doc.uri, []);
    }
    else {
        out.appendLine('✗ Fehler (siehe oben).');
        if (lang === 'hack-asm')
            DIAG.set(doc.uri, parseAsmErrors(stderr, doc));
        if (lang === 'jack')
            DIAG.set(doc.uri, parseJackErrors(stderr, doc));
    }
}
// ── JAR-Prozess ───────────────────────────────────────────────────────────────
function runJar(jar, args, cb) {
    let stdout = '', stderr = '';
    const proc = (0, child_process_1.spawn)('java', ['-jar', jar, ...args]);
    proc.stdout.on('data', d => { stdout += d.toString(); });
    proc.stderr.on('data', d => { stderr += d.toString(); });
    proc.on('close', code => cb(code ?? 1, stdout, stderr));
}
//# sourceMappingURL=extension.js.map