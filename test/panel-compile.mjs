// Compiles the inline <script> blocks of panel.html.
// The panel has no build step: a syntax error there only shows up at runtime,
// inside WebView2, which is the most annoying place to discover it.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const html = readFileSync(join(root, 'panel.html'), 'utf8');

const blocks = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);
if (blocks.length === 0) {
  console.error('panel.html: 没有找到内联 <script>');
  process.exit(1);
}

let compiled = 0;
for (const [index, source] of blocks.entries()) {
  try {
    new Function(source);
    compiled += 1;
  } catch (error) {
    console.error(`panel.html: 第 ${index + 1} 段内联脚本编译失败 — ${error.message}`);
    process.exitCode = 1;
  }
}

console.log(`panel.html: ${compiled}/${blocks.length} 段内联脚本编译通过`);
