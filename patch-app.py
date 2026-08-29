from pathlib import Path
import re

path = Path('/app/public/app.js')
text = path.read_text(encoding='utf-8')

# Do not block the first paint while every category row is fetched.
old_call = '        await this.renderCategoryRows();'
new_call = "        this.renderCategoryRows().catch((err) => console.warn('Background category rows load failed:', err));"
if old_call in text:
    text = text.replace(old_call, new_call, 1)

pattern = re.compile(r"  async renderCategoryRows\(\) \{.*?\n  \}\n\n  _buildTrackHtml", re.S)
replacement = '''  async renderCategoryRows() {
    const container = this.$('#streamContent');
    if (!container) return;

    // Paint the latest row immediately. Category rows are fetched in parallel
    // and appended as they arrive instead of blocking the whole homepage.
    let html = '';
    if (Array.isArray(this.posts['latest']) && this.posts['latest'].length > 0) {
      html = this._buildTrackHtml('latest', 'Latest Releases', this.posts['latest']);
    }
    container.innerHTML = html;

    // Attach delegated handlers once. Appending rows below does not remove
    // this listener because the container itself is never replaced again.
    if (!container.dataset.pencarimovieEventsBound) {
      container.dataset.pencarimovieEventsBound = '1';

      container.addEventListener('click', (e) => {
        const viewAllBtn = e.target.closest('.stream-content-row__view-all');
        if (viewAllBtn) {
          const slug = viewAllBtn.getAttribute('data-category');
          const cat = this.categories.find(c => c.slug === slug);
          if (slug === 'latest') {
            this.openCategoryPage(slug, 'Latest Releases');
          } else {
            this.openCategoryPage(slug, cat ? cat.name : slug);
          }
          return;
        }

        const card = e.target.closest('.stream-file-card');
        if (card) {
          const shortCode = card.getAttribute('data-short-code');
          if (shortCode) this.openFileDetail(shortCode);
          return;
        }

        const postCard = e.target.closest('.stream-card');
        if (postCard) {
          const postId = postCard.getAttribute('data-post-id');
          if (postId) {
            let postData = null;
            for (const key of Object.keys(this.posts)) {
              const arr = this.posts[key];
              if (Array.isArray(arr)) {
                postData = arr.find((p) => String(p.id) === postId || String(p.ID) === postId);
                if (postData) break;
              }
            }
            if (postData) {
              this.openModal(postData);
            } else {
              this.openModal({ id: postId, post_title: postCard.getAttribute('data-post-title') || 'Details' });
            }
          }
        }
      });
    }

    const bindArrows = (root) => {
      root.querySelectorAll('.stream-content-row__arrow').forEach((btn) => {
        if (btn.dataset.pencarimovieArrowBound) return;
        btn.dataset.pencarimovieArrowBound = '1';
        btn.addEventListener('click', () => {
          const trackId = btn.getAttribute('data-track');
          const track = this.$(`#track-${trackId}`);
          if (!track) return;
          const dir = btn.classList.contains('stream-content-row__arrow--left') ? -1 : 1;
          track.scrollBy({ left: dir * 300, behavior: 'smooth' });
        });
      });
    };

    bindArrows(container);

    const loadCategory = async (cat) => {
      try {
        const posts = await this.fetchStream('posts', { category: cat.slug, limit: 10 });
        if (!Array.isArray(posts) || posts.length === 0) return;

        this.posts[cat.slug] = posts;
        container.insertAdjacentHTML('beforeend', this._buildTrackHtml(cat.slug, cat.name, posts));
        const row = this.$(`#row-${cat.slug}`);
        if (row) bindArrows(row);
      } catch (_) {
        // Silently skip failed categories.
      }
    };

    // Fetch category rows concurrently. This removes the N x network latency
    // caused by the old sequential loop.
    await Promise.all(this.categories.map(loadCategory));
  }

  _buildTrackHtml'''

text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit('Expected renderCategoryRows function was not found')

# Do not make the browser wait for trending/categories/category rows before
# showing the actual application shell. The old implementation awaited three
# backend calls and then awaited every category row before hiding the loader.
# On Render this made a perfectly healthy server feel frozen while the remote
# WordPress API was responding.
load_pattern = re.compile(r"  async loadInitialData\(\) \{.*?\n  \}\n\n  renderNavLinks", re.S)
load_replacement = '''  async loadInitialData() {
    // First paint must not depend on the remote WordPress/Telegram-backed API.
    // Render the shell immediately, then progressively fill it with data.
    this.showLoading(false);

    const fallbackCategories = [
      { name: 'Animation', slug: 'animation' },
      { name: 'Action', slug: 'action' },
      { name: 'Comedy', slug: 'comedy' },
      { name: 'Drama', slug: 'drama' },
      { name: 'Horror', slug: 'horror' },
      { name: 'Sci-Fi', slug: 'sci-fi' },
      { name: 'Thriller', slug: 'thriller' },
      { name: 'Malay', slug: 'malay' },
      { name: 'Indo', slug: 'indo' },
      { name: 'Korean', slug: 'korean' }
    ];

    // Paint useful navigation and empty-state content immediately.
    this.categories = fallbackCategories;
    this.renderNavLinks();
    this.renderHero([]);
    this.renderTrending();
    this.renderSearchChips();

    // Load each expensive data group independently. The first response wins
    // and updates only the part of the page that depends on it.
    this.fetchStream('categories')
      .then((data) => {
        if (Array.isArray(data) && data.length > 0) {
          this.categories = data;
          this.renderNavLinks();
          this.renderCategoryRows().catch((err) => console.warn('Background category rows load failed:', err));
        }
      })
      .catch((err) => console.warn('Categories load failed:', err));

    this.fetchStream('trending', { limit: 10 })
      .then((data) => {
        this.trending = Array.isArray(data) ? data : [];
        this.renderTrending();
      })
      .catch((err) => console.warn('Trending load failed:', err));

    this.fetchStream('posts', { limit: 12 })
      .then((data) => {
        const latestData = Array.isArray(data) ? data : [];
        this.posts['latest'] = latestData;
        this.renderHero(latestData);
        this.renderCategoryRows().catch((err) => console.warn('Latest rows load failed:', err));
      })
      .catch((err) => console.warn('Latest posts load failed:', err));
  }

  renderNavLinks'''

text, count = load_pattern.subn(load_replacement, text, count=1)
if count != 1:
    raise SystemExit('Expected loadInitialData function was not found')

path.write_text(text, encoding='utf-8')
print('PencariMovie frontend performance patch applied')
