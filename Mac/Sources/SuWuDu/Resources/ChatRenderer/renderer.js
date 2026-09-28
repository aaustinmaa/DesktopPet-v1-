/* Local rendering only: raw HTML is text, images are labels, math is untrusted. */
const chatMarkdown = markdownit({ html: false, breaks: true, linkify: true });
function mathHTML(source, display) {
    try {
        return katex.renderToString(source, { displayMode: display, throwOnError: true,
            trust: false, strict: 'ignore', maxExpand: 1000, maxSize: 20 });
    } catch (_) {
        return '<code class="math-fallback">' + chatMarkdown.utils.escapeHtml(source) + '</code>';
    }
}
chatMarkdown.inline.ruler.before('escape', 'chat_math', (state, silent) => {
    const tail = state.src.slice(state.pos);
    const open = ['\\(', '\\[', '$$', '$'].find(x => tail.startsWith(x));
    if (!open) return false;
    const close = open === '\\(' ? '\\)' : open === '\\[' ? '\\]' : open;
    if (open === '$' && /\s/.test(tail[1] || ' ')) return false;
    let end = open.length;
    while ((end = tail.indexOf(close, end)) !== -1) {
        if (tail[end - 1] !== '\\') break;
        end += close.length;
    }
    if (end < 0 || end === open.length) return false;
    if (open === '$' && (/\s/.test(tail[end - 1]) || /\d/.test(tail[end + 1] || ''))) return false;
    if (!silent) {
        const token = state.push('chat_math', '', 0);
        token.content = tail.slice(open.length, end);
        token.meta = { display: open === '\\[' || open === '$$' };
    }
    state.pos += end + close.length;
    return true;
});
chatMarkdown.block.ruler.before('fence', 'chat_math_block', (state, start, end, silent) => {
    const first = state.src.slice(state.bMarks[start] + state.tShift[start], state.eMarks[start]);
    const open = first.startsWith('\\[') ? '\\[' : first.startsWith('$$') ? '$$' : null;
    if (!open) return false;
    const close = open === '\\[' ? '\\]' : '$$';
    let content = first.slice(open.length), line = start;
    while (!content.includes(close) && ++line < end) {
        content += '\n' + state.src.slice(state.bMarks[line] + state.tShift[line], state.eMarks[line]);
    }
    const closing = content.indexOf(close);
    if (closing < 0 || content.slice(closing + close.length).trim()) return false;
    if (silent) return true;
    const token = state.push('chat_math_block', '', 0);
    token.content = content.slice(0, closing);
    token.map = [start, line + 1];
    state.line = line + 1;
    return true;
}, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });
chatMarkdown.renderer.rules.chat_math = (tokens, i) => mathHTML(tokens[i].content, tokens[i].meta.display);
chatMarkdown.renderer.rules.chat_math_block = (tokens, i) => mathHTML(tokens[i].content, true);
chatMarkdown.renderer.rules.image = (tokens, i) => '<span>' + chatMarkdown.utils.escapeHtml(tokens[i].content || '图片') + '</span>';
function renderChatMessage(source) { return chatMarkdown.render(source); }
function updateMessage(source) {
    const content = document.getElementById('content');
    try { content.innerHTML = renderChatMessage(source); }
    catch (_) { content.textContent = source; }
    reportHeight();
    document.fonts.ready.then(reportHeight);
}
function reportHeight() {
    window.webkit?.messageHandlers?.height?.postMessage(Math.ceil(document.getElementById('content').getBoundingClientRect().height));
}
if (typeof document !== 'undefined') {
    new ResizeObserver(reportHeight).observe(document.getElementById('content'));
}
