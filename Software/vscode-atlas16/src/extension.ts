import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { spawn } from 'child_process';

const DIAG = vscode.languages.createDiagnosticCollection('atlas16');

export function activate(ctx: vscode.ExtensionContext) {
    ctx.subscriptions.push(DIAG);

    // Diagnostics bei Speichern
    ctx.subscriptions.push(
        vscode.workspace.onDidSaveTextDocument(doc => {
            if (doc.languageId === 'hack-asm') validateAsm(doc);
            if (doc.languageId === 'jack')     validateJack(doc);
        })
    );

    // Befehle
    ctx.subscriptions.push(
        vscode.commands.registerCommand('atlas16.compile', () => runBuild(false)),
        vscode.commands.registerCommand('atlas16.compileAndLoad', () => runBuild(true))
    );
}

export function deactivate() { DIAG.clear(); }

// ── JAR-Pfad ermitteln ────────────────────────────────────────────────────────

function jarPath(): string | null {
    const cfg = vscode.workspace.getConfiguration('atlas16').get<string>('jarPath');
    if (cfg && cfg.length > 0 && fs.existsSync(cfg)) return cfg;

    // Workspace nach atlas16.jar durchsuchen
    const folders = vscode.workspace.workspaceFolders;
    if (!folders) return null;
    for (const folder of folders) {
        const candidate = path.join(folder.uri.fsPath, 'Software', 'atlas16', 'target', 'atlas16.jar');
        if (fs.existsSync(candidate)) return candidate;
    }
    return null;
}

// ── Validierung / Diagnostics ─────────────────────────────────────────────────

function validateAsm(doc: vscode.TextDocument) {
    const jar = jarPath();
    if (!jar) { DIAG.set(doc.uri, []); return; }

    runJar(jar, ['asm', doc.fileName, '-o', '/dev/null'], (code, stdout, stderr) => {
        DIAG.set(doc.uri, parseAsmErrors(stderr, doc));
    });
}

function validateJack(doc: vscode.TextDocument) {
    const jar = jarPath();
    if (!jar) { DIAG.set(doc.uri, []); return; }

    runJar(jar, ['jack', doc.fileName], (code, _out, stderr) => {
        DIAG.set(doc.uri, parseJackErrors(stderr, doc));
    });
}

function parseAsmErrors(stderr: string, doc: vscode.TextDocument): vscode.Diagnostic[] {
    const diags: vscode.Diagnostic[] = [];
    // Format: "Zeile 42: Unbekannter comp-Wert 'XY'."
    const re = /Zeile\s+(\d+):\s+(.+)/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(stderr)) !== null) {
        const line = Math.max(0, parseInt(m[1]) - 1);
        const range = doc.lineAt(Math.min(line, doc.lineCount - 1)).range;
        diags.push(new vscode.Diagnostic(range, m[2], vscode.DiagnosticSeverity.Error));
    }
    // Fallback: beliebige Fehler-Zeile
    if (diags.length === 0 && stderr.includes('Fehler:')) {
        const msg = stderr.replace(/^Fehler:\s*/m, '').trim();
        if (msg) diags.push(new vscode.Diagnostic(
            new vscode.Range(0, 0, 0, 0), msg, vscode.DiagnosticSeverity.Error));
    }
    return diags;
}

function parseJackErrors(stderr: string, doc: vscode.TextDocument): vscode.Diagnostic[] {
    const diags: vscode.Diagnostic[] = [];
    if (stderr.includes('Fehler:')) {
        const msg = stderr.replace(/^Fehler:\s*/m, '').trim();
        if (msg) diags.push(new vscode.Diagnostic(
            new vscode.Range(0, 0, 0, 0), msg, vscode.DiagnosticSeverity.Error));
    }
    return diags;
}

// ── Build & Upload ────────────────────────────────────────────────────────────

async function runBuild(withLoad: boolean) {
    const editor = vscode.window.activeTextEditor;
    if (!editor) { vscode.window.showErrorMessage('Kein aktiver Editor.'); return; }

    const doc  = editor.document;
    const lang = doc.languageId;
    if (lang !== 'hack-asm' && lang !== 'jack') {
        vscode.window.showErrorMessage('Aktive Datei ist kein .asm oder .jack.');
        return;
    }

    const jar = jarPath();
    if (!jar) {
        vscode.window.showErrorMessage(
            'atlas16.jar nicht gefunden. Bitte atlas16.jarPath in den Einstellungen konfigurieren.');
        return;
    }

    await doc.save();

    const cfg  = vscode.workspace.getConfiguration('atlas16');
    const ip   = cfg.get<string>('deviceIp') ?? '';
    const user = cfg.get<string>('sshUser') ?? 'root';

    const out = vscode.window.createOutputChannel('Atlas 16');
    out.show(true);
    out.appendLine(`── Atlas 16 Build ──────────────────────────────`);

    return new Promise<void>(resolve => {
        // Jack: ein einziger `build`-Aufruf macht alles
        if (lang === 'jack') {
            const args = ['build', doc.fileName, ...(withLoad && ip ? ['--ip', ip, '--user', user] : [])];
            out.appendLine(`java -jar atlas16.jar ${args.join(' ')}`);
            runJar(jar, args, (code, stdout, stderr) => {
                if (stdout) out.append(stdout);
                if (stderr) out.append(stderr);
                finalize(code, stderr, doc, lang, out);
                resolve();
            });
            return;
        }

        // Hack-ASM: erst asm, dann optional load
        const hackFile = doc.fileName.replace(/\.asm$/, '.hack');
        const asmArgs  = ['asm', doc.fileName, '-o', hackFile];
        out.appendLine(`java -jar atlas16.jar ${asmArgs.join(' ')}`);
        runJar(jar, asmArgs, (code, stdout, stderr) => {
            if (stdout) out.append(stdout);
            if (stderr) out.append(stderr);
            if (code !== 0) { finalize(code, stderr, doc, lang, out); resolve(); return; }
            if (!withLoad || !ip) { finalize(0, '', doc, lang, out); resolve(); return; }

            const loadArgs = ['load', hackFile, '--ip', ip, '--user', user];
            out.appendLine(`java -jar atlas16.jar ${loadArgs.join(' ')}`);
            runJar(jar, loadArgs, (code2, stdout2, stderr2) => {
                if (stdout2) out.append(stdout2);
                if (stderr2) out.append(stderr2);
                finalize(code2, stderr2, doc, lang, out);
                resolve();
            });
        });
    });
}

function finalize(
    code: number, stderr: string,
    doc: vscode.TextDocument, lang: string,
    out: vscode.OutputChannel
) {
    if (code === 0) {
        out.appendLine('✓ Erfolgreich.');
        vscode.window.setStatusBarMessage('Atlas 16: ✓ Fertig', 4000);
        DIAG.set(doc.uri, []);
    } else {
        out.appendLine('✗ Fehler (siehe oben).');
        if (lang === 'hack-asm') DIAG.set(doc.uri, parseAsmErrors(stderr, doc));
        if (lang === 'jack')     DIAG.set(doc.uri, parseJackErrors(stderr, doc));
    }
}

// ── JAR-Prozess ───────────────────────────────────────────────────────────────

function runJar(
    jar: string,
    args: string[],
    cb: (code: number, stdout: string, stderr: string) => void
) {
    let stdout = '', stderr = '';
    const proc = spawn('java', ['-jar', jar, ...args]);
    proc.stdout.on('data', d => { stdout += d.toString(); });
    proc.stderr.on('data', d => { stderr += d.toString(); });
    proc.on('close', code => cb(code ?? 1, stdout, stderr));
}
