const fs = require('fs');
const path = require('path');

const DATA_FILE = path.join(__dirname, 'store-data.json');

const plans = {
  free:        { id: 'free',        name: 'Free',        price: 0,      maxDevices: 1,   days: 0 },
  pro_monthly: { id: 'pro_monthly', name: 'Pro Monthly', price: 19900,  maxDevices: 5,   days: 30 },
  pro_yearly:  { id: 'pro_yearly',  name: 'Pro Yearly',  price: 199000, maxDevices: 5,   days: 365 },
  team_monthly:{ id: 'team_monthly',name: 'Team Monthly', price: 149900, maxDevices: 999, days: 30 },
  team_yearly: { id: 'team_yearly', name: 'Team Yearly',  price: 1499000,maxDevices: 999, days: 365 },
};

// ----- Persistence -----
let data = { users: {}, licenseKeys: {} };
let _writeTimeout = null;

function load() {
  try {
    if (fs.existsSync(DATA_FILE)) {
      data = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    }
  } catch (e) {
    console.error('Store load error:', e.message);
  }
}

function save() {
  if (_writeTimeout) clearTimeout(_writeTimeout);
  _writeTimeout = setTimeout(() => {
    try {
      fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
    } catch (e) {
      console.error('Store save error:', e.message);
    }
  }, 200);
}

load();

// ----- Users -----
function getUser(uid) {
  if (!data.users[uid]) {
    data.users[uid] = { uid, plan: 'free', createdAt: new Date().toISOString(), email: '', planExpiresAt: null };
    save();
  }
  return data.users[uid];
}

function setUserPlan(uid, planId) {
  const user = getUser(uid);
  const plan = plans[planId];
  if (!plan) return user;
  user.plan = planId;
  if (plan.days > 0) {
    const d = new Date();
    d.setDate(d.getDate() + plan.days);
    user.planExpiresAt = d.toISOString();
  } else {
    user.planExpiresAt = null;
  }
  save();
  return user;
}

function getUserPlan(uid) {
  const user = getUser(uid);
  const plan = plans[user.plan] || plans.free;
  const expired = user.planExpiresAt && new Date(user.planExpiresAt) < new Date();
  if (expired && user.plan !== 'free') {
    user.plan = 'free';
    user.planExpiresAt = null;
    save();
  }
  const pl = plans[user.plan] || plans.free;
  return { plan: user.plan, maxDevices: pl.maxDevices, expiresAt: user.planExpiresAt };
}

function getMaxDevices(uid) {
  const user = getUser(uid);
  const expired = user.planExpiresAt && new Date(user.planExpiresAt) < new Date();
  if (expired && user.plan !== 'free') {
    user.plan = 'free';
    user.planExpiresAt = null;
    save();
  }
  const plan = plans[user.plan] || plans.free;
  return plan.maxDevices;
}

function cancelPlan(uid) {
  const user = getUser(uid);
  user.plan = 'free';
  user.planExpiresAt = null;
  save();
  return user;
}

// ----- License Keys -----
function generateKey() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let key = 'SEELO-';
  for (let i = 0; i < 8; i++) key += chars[Math.floor(Math.random() * chars.length)];
  key += '-';
  for (let i = 0; i < 8; i++) key += chars[Math.floor(Math.random() * chars.length)];
  return key;
}

function addLicenseKey(planId, durationDays, customerInfo) {
  if (!plans[planId]) return null;
  const key = generateKey();
  data.licenseKeys[key] = {
    plan: planId,
    durationDays: durationDays || 30,
    customerName: (customerInfo && customerInfo.name) || '',
    customerEmail: (customerInfo && customerInfo.email) || '',
    amountPaid: (customerInfo && customerInfo.amount) || 0,
    notes: (customerInfo && customerInfo.notes) || '',
    usedBy: null,
    activatedAt: null,
    createdAt: new Date().toISOString(),
  };
  save();
  return key;
}

function listLicenseKeys() {
  return Object.entries(data.licenseKeys).map(([k, v]) => ({ key: k, ...v }));
}

function exportKeysCSV() {
  const rows = [['Key', 'Plan', 'Duration (days)', 'Customer Name', 'Customer Email', 'Amount Paid', 'Notes', 'Created', 'Status', 'Activated By', 'Activated At']];
  Object.entries(data.licenseKeys).forEach(([k, v]) => {
    const status = v.usedBy ? 'Used' : 'Available';
    rows.push([k, v.plan, v.durationDays, v.customerName, v.customerEmail, v.amountPaid, v.notes, v.createdAt, status, v.usedBy || '', v.activatedAt || '']);
  });
  return rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n');
}

function activateKey(key, uid) {
  const entry = data.licenseKeys[key];
  if (!entry) return { error: 'Invalid key' };
  if (entry.usedBy) return { error: 'Key already used' };

  const plan = plans[entry.plan];
  if (!plan) return { error: 'Invalid plan in key' };

  setUserPlan(uid, entry.plan);
  entry.usedBy = uid;
  entry.activatedAt = new Date().toISOString();
  save();

  return { success: true, plan: entry.plan, maxDevices: plan.maxDevices, expiresAt: getUserPlan(uid).expiresAt };
}

// ----- Plans list -----
function getPlans() {
  return Object.values(plans).map(p => ({
    id: p.id, name: p.name, price: p.price, maxDevices: p.maxDevices,
  }));
}

function _raw() { return data; }

// Immediate synchronous write (for graceful shutdown)
function forceSave() {
  if (_writeTimeout) clearTimeout(_writeTimeout);
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('Force save error:', e.message);
  }
}

module.exports = {
  getUser, setUserPlan, getUserPlan, getMaxDevices,
  cancelPlan,
  addLicenseKey, listLicenseKeys, activateKey, exportKeysCSV,
  getPlans, plans,
  _raw, forceSave,
};
