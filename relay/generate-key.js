/**
 * License Key Manager — run from relay/ directory:
 *
 * Generate a key:
 *   node generate-key.js pro_yearly 365 "John" "john@email.com" 1990 "note"
 *   node generate-key.js pro_monthly 30
 *
 * List all keys:
 *   node generate-key.js list
 *
 * Export to CSV:
 *   node generate-key.js csv
 */
const store = require('./store');

const command = process.argv[2];

// ── List all keys ──
if (command === 'list') {
  const keys = store.listLicenseKeys();
  if (keys.length === 0) {
    console.log('No license keys found.');
    process.exit(0);
  }
  console.log('');
  console.log('Key                          Plan            Days  Customer          Status       Used By');
  console.log('──────────────────────────── ─────────────── ───── ───────────────── ──────────── ──────────');
  keys.forEach(k => {
    const status = k.usedBy ? 'USED' : 'AVAILABLE';
    const name = (k.customerName || '').padEnd(16).slice(0, 16);
    const plan = k.plan.padEnd(14).slice(0, 14);
    const used = (k.usedBy || '').padEnd(10).slice(0, 10);
    console.log(`${k.key.padEnd(28)} ${plan} ${String(k.durationDays).padEnd(4)} ${name} ${status.padEnd(12)} ${used}`);
  });
  console.log(`\nTotal: ${keys.length} keys (${keys.filter(k => k.usedBy).length} used, ${keys.filter(k => !k.usedBy).length} available)`);
  process.exit(0);
}

// ── Export CSV ──
if (command === 'csv') {
  console.log(store.exportKeysCSV());
  process.exit(0);
}

// ── Generate key ──
const planId = command;
const durationDays = parseInt(process.argv[3], 10) || 30;
const customerName = process.argv[4] || '';
const customerEmail = process.argv[5] || '';
const amountPaid = parseInt(process.argv[6], 10) || 0;
const notes = process.argv[7] || '';

if (!planId) {
  console.log('Usage:');
  console.log('  Generate: node generate-key.js <planId> [days] [name] [email] [amount] [notes]');
  console.log('  List:     node generate-key.js list');
  console.log('  CSV:      node generate-key.js csv');
  console.log('');
  console.log('Available plans:');
  store.getPlans().filter(p => p.id !== 'free').forEach(p => {
    console.log(`  ${p.id}  — ${p.name}  (${p.maxDevices} devices)`);
  });
  process.exit(1);
}

const key = store.addLicenseKey(planId, durationDays, {
  name: customerName,
  email: customerEmail,
  amount: amountPaid,
  notes: notes,
});

if (!key) {
  console.error('Invalid plan ID. Use one of:', Object.keys(store.plans).filter(k => k !== 'free').join(', '));
  process.exit(1);
}

console.log(`LICENSE_KEY:${key}`);
console.log(`PLAN:${planId}`);
console.log(`DURATION:${durationDays} days`);
if (customerName) console.log(`CUSTOMER:${customerName}`);
if (amountPaid) console.log(`AMOUNT:₹${amountPaid}`);

// Save immediately
store.forceSave();
