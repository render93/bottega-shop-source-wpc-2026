// Synthetic shoppers for Bottega Aurora: random carts of 1-3 products at a constant rate.
// Env: TARGET_URL (required), RATE (checkouts per TIME_UNIT, default 12), TIME_UNIT (k6 format,
// default 1m), DURATION (k6 format, default 150m), PROMO_SHARE (share of carts with a promo code, default 0.08).
import http from 'k6/http';

const TARGET_URL = __ENV.TARGET_URL;
const PROMO_SHARE = Number(__ENV.PROMO_SHARE || '0.08');
const SKUS = [
  'panettone-classico', 'panettone-cioccolato', 'pandoro', 'pandoro-farcito',
  'torrone', 'panforte', 'ricciarelli', 'cantucci',
];

export const options = {
  discardResponseBodies: true,
  scenarios: {
    shoppers: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || '12'),
      timeUnit: __ENV.TIME_UNIT || '1m',
      duration: __ENV.DURATION || '150m',
      // A small shop: one checkout every few seconds needs only a handful of virtual users.
      preAllocatedVUs: 5,
      maxVUs: 20,
    },
  },
};

export function setup() {
  if (!TARGET_URL) throw new Error('TARGET_URL is required');
}

function randomCart() {
  const pool = [...SKUS];
  const lines = 1 + Math.floor(Math.random() * 3);
  const items = [];
  for (let i = 0; i < lines; i++) {
    const sku = pool.splice(Math.floor(Math.random() * pool.length), 1)[0];
    items.push({ sku, qty: 1 + Math.floor(Math.random() * 2) });
  }
  return items;
}

export default function () {
  const body = JSON.stringify({
    items: randomCart(),
    promo: Math.random() < PROMO_SHARE ? 'AURORA10' : null,
  });
  // Failed checkouts (500) are part of the scenario: no checks, no thresholds.
  http.post(`${TARGET_URL}/api/checkout`, body, {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'checkout' },
  });
}
