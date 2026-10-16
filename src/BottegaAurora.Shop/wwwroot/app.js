'use strict';

const REFRESH_MS = 2000;
const FEED_SIZE = 15;

const eurWhole = new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });
const eurCents = new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR' });
const clock = new Intl.DateTimeFormat('it-IT', { hour: '2-digit', minute: '2-digit', second: '2-digit' });

const $ = (id) => document.getElementById(id);

// Simple product illustrations, one shape per product family.
const ART = {
  'panettone-classico': dome('#e2b268', '#a5652a'),
  'panettone-cioccolato': dome('#c9965a', '#4a2a17'),
  'pandoro': star('#f1cf7a', '#c9962e'),
  'pandoro-farcito': star('#f4dfa5', '#b77c2b'),
  'torrone': bar('#f3ead8', '#b98a52'),
  'panforte': disc('#7a3e1d', '#3f1d0c'),
  'ricciarelli': cookies('#f5ead3', '#c9b48b'),
  'cantucci': cookies('#e3b878', '#9c6a2e'),
};

function dome(fill, top) {
  return `<svg viewBox="0 0 120 90" aria-hidden="true"><rect x="22" y="44" width="76" height="38" rx="4" fill="#6b1d2a"/><path d="M22 46 Q60 -6 98 46 Z" fill="${fill}"/><path d="M30 34 Q60 4 90 34" stroke="${top}" stroke-width="5" fill="none"/></svg>`;
}
function star(fill, shade) {
  return `<svg viewBox="0 0 120 90" aria-hidden="true"><polygon points="60,6 74,34 104,38 82,58 88,86 60,72 32,86 38,58 16,38 46,34" fill="${fill}" stroke="${shade}" stroke-width="3"/></svg>`;
}
function bar(fill, nuts) {
  return `<svg viewBox="0 0 120 90" aria-hidden="true"><rect x="12" y="30" width="96" height="32" rx="4" fill="${fill}" stroke="#d9cbb0"/><circle cx="34" cy="46" r="5" fill="${nuts}"/><circle cx="60" cy="42" r="5" fill="${nuts}"/><circle cx="86" cy="48" r="5" fill="${nuts}"/></svg>`;
}
function disc(fill, edge) {
  return `<svg viewBox="0 0 120 90" aria-hidden="true"><ellipse cx="60" cy="50" rx="46" ry="28" fill="${edge}"/><ellipse cx="60" cy="44" rx="46" ry="28" fill="${fill}"/><circle cx="46" cy="40" r="4" fill="#d4a64a"/><circle cx="72" cy="48" r="4" fill="#d4a64a"/></svg>`;
}
function cookies(fill, edge) {
  return `<svg viewBox="0 0 120 90" aria-hidden="true"><ellipse cx="40" cy="50" rx="24" ry="16" fill="${fill}" stroke="${edge}" stroke-width="3"/><ellipse cx="80" cy="44" rx="24" ry="16" fill="${fill}" stroke="${edge}" stroke-width="3"/></svg>`;
}

// ----- Mode: storefront (/) or control room (/#sala) -----
function applyMode() {
  const control = location.hash === '#sala';
  $('shop').hidden = control;
  $('control').hidden = !control;
  if (control) refreshFeed();
}
window.addEventListener('hashchange', applyMode);

// ----- Storefront -----
const cart = new Map();
let products = [];

async function loadProducts() {
  const response = await fetch('/api/products', { cache: 'no-store' });
  products = await response.json();
  $('products').innerHTML = products.map((p) => `
    <article class="product">
      ${ART[p.sku] ?? ''}
      <h3>${p.name}</h3>
      <p>${p.description}</p>
      <div class="product-buy">
        <span class="price">${eurCents.format(p.price)}</span>
        <button class="add" type="button" data-sku="${p.sku}">Aggiungi</button>
      </div>
    </article>`).join('');
}

$('products').addEventListener('click', (event) => {
  const sku = event.target.dataset?.sku;
  if (!sku) return;
  cart.set(sku, Math.min((cart.get(sku) ?? 0) + 1, 10));
  renderCart();
});

function renderCart() {
  let count = 0;
  let total = 0;
  $('cart-lines').innerHTML = [...cart].map(([sku, qty]) => {
    const p = products.find((x) => x.sku === sku);
    count += qty;
    total += p.price * qty;
    return `<li><span>${p.name} x${qty}</span><span>${eurCents.format(p.price * qty)}</span></li>`;
  }).join('');
  $('cart-count').textContent = count;
  $('cart-total').textContent = eurCents.format(total);
  $('pay').disabled = count === 0;
}

$('cart-button').addEventListener('click', () => { $('cart').hidden = false; });
$('cart-close').addEventListener('click', () => { $('cart').hidden = true; });

$('pay').addEventListener('click', async () => {
  $('pay').disabled = true;
  $('pay-result').textContent = '';
  const items = [...cart].map(([sku, qty]) => ({ sku, qty }));
  try {
    const response = await fetch('/api/checkout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ items, promo: null }),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const order = await response.json();
    $('pay-result').textContent = `Ordine #${order.orderId} confermato`;
    cart.clear();
  } catch {
    $('pay-result').textContent = 'Pagamento non riuscito, riprova tra qualche minuto';
  }
  renderCart();
});

// ----- Live data -----
let liveBusy = false;
let feedBusy = false;
const stale = { live: false, feed: false };
function showStale() {
  $('status').textContent = stale.live || stale.feed ? '· dati non disponibili' : '';
}

async function refreshLive() {
  if (liveBusy) return;
  liveBusy = true;
  try {
    try {
      const response = await fetch('/api/live', { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const d = await response.json();
      const failing = d.failedLastMinute > d.ordersLastMinute;
      $('ticker-orders').textContent = d.ordersLastMinute;
      $('ticker-orders').className = failing ? 'bad' : 'ok';
      $('ticker-revenue').textContent = eurWhole.format(d.revenueToday);
      $('ticker-lost').textContent = eurWhole.format(d.lostToday);
      $('orders').textContent = d.ordersLastMinute;
      $('orders').className = 'tile-value ' + (failing ? 'bad' : 'ok');
      $('failed').textContent = d.failedLastMinute;
      $('revenue').textContent = eurWhole.format(d.revenueToday);
      $('lost').textContent = eurWhole.format(d.lostToday);
      $('version').textContent = d.version;
      $('updated').textContent = clock.format(new Date());
      stale.live = false;
      showStale();
    } catch {
      // Keep the last numbers on screen; just say the data is stale.
      stale.live = true;
      showStale();
    }
  } finally {
    liveBusy = false;
  }
}

let lastId = null;
const feedRows = [];

async function refreshFeed() {
  if (location.hash !== '#sala') return;
  if (feedBusy) return;
  feedBusy = true;
  try {
    try {
      const url = lastId === null ? '/api/orders/feed' : `/api/orders/feed?after=${lastId}`;
      const response = await fetch(url, { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const entries = await response.json();
      for (const e of entries) {
        if (lastId !== null && e.id <= lastId) continue;
        feedRows.unshift(e);
        lastId = e.id;
      }
      feedRows.splice(FEED_SIZE);
      $('feed').innerHTML = feedRows.map((e) => {
        const ok = e.status === 'Completed';
        return `<li>
        <span class="dot ${ok ? 'ok' : 'bad'}"></span>
        <span>${clock.format(new Date(e.createdAt))}</span>
        <span>#${e.id}</span>
        <span class="items">${e.items}</span>
        <span class="amount">${eurCents.format(e.amount)}</span>
        <span class="outcome ${ok ? 'ok' : 'bad'}">${ok ? 'completato' : 'pagamento non riuscito'}</span>
      </li>`;
      }).join('');
      stale.feed = false;
      showStale();
    } catch {
      stale.feed = true;
      showStale();
    }
  } finally {
    feedBusy = false;
  }
}

applyMode();
loadProducts().then(renderCart);
refreshLive();
refreshFeed();
setInterval(() => { refreshLive(); refreshFeed(); }, REFRESH_MS);
