from pathlib import Path

path = Path('/app/public/app.js')
text = path.read_text(encoding='utf-8')

# The first performance patch loads every category row in parallel. That is
# better than sequential requests, but on a small Render instance it can still
# create a burst of remote WordPress requests. Keep the first four rows eager
# and defer the rest until the browser is idle.
old = "    await Promise.all(this.categories.map(loadCategory));"
new = """    const initialCategories = this.categories.slice(0, 4);
    await Promise.all(initialCategories.map(loadCategory));

    const remainingCategories = this.categories.slice(4);
    const loadRemaining = () => Promise.all(remainingCategories.map(loadCategory)).catch(() => {});
    if (remainingCategories.length) {
      if ('requestIdleCallback' in window) {
        window.requestIdleCallback(loadRemaining, { timeout: 2500 });
      } else {
        setTimeout(loadRemaining, 1200);
      }
    }"""
if old in text:
    text = text.replace(old, new, 1)

# The latest-posts response already starts category loading. Do not start the
# same work again when the categories metadata response arrives first.
old = "          this.renderCategoryRows().catch((err) => console.warn('Background category rows load failed:', err));\n"
text = text.replace(old, "", 1)

# Make browser media elements explicitly use the browser's automatic preload
# strategy. The app already assigns the stream URL and calls load() immediately;
# this tells Chromium/Edge/Safari to fetch media data as soon as the source is
# known, improving time-to-first-frame without downloading the whole movie.
old = "  _startMediaStream(mediaEl, url, poster = '') {\n    if (!mediaEl || !url) return;\n\n    this._clearPlayerRetry();"
new = "  _startMediaStream(mediaEl, url, poster = '') {\n    if (!mediaEl || !url) return;\n\n    // Start browser media buffering immediately. This is intentionally only a\n    // preload hint; the backend remains responsible for HTTP Range streaming.\n    mediaEl.preload = 'auto';\n    if (mediaEl.tagName === 'VIDEO') mediaEl.setAttribute('playsinline', '');\n\n    this._clearPlayerRetry();"
if old in text:
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
print('Secondary PencariMovie performance patch applied')
