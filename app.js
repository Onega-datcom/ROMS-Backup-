const KEYS = ['ingredients', 'recipes', 'inventoryTransactions', 'productionLogs', 'revenueRecords', 'wasteLogs', 'physicalCounts', 'users', 'reservations', 'restaurantTables'];
const seed = {
  ingredients: [
    { id: 'ing-1', name: 'Mozzarella Cheese', category: 'Dairy', unit: 'kg', cost: 420, stock: 12.5, minimum: 8 },
    { id: 'ing-2', name: 'Pizza Flour', category: 'Dry Goods', unit: 'kg', cost: 68, stock: 42, minimum: 25 },
    { id: 'ing-3', name: 'Tomato Sauce', category: 'Sauces', unit: 'L', cost: 145, stock: 9, minimum: 12 },
    { id: 'ing-4', name: 'Pepperoni', category: 'Meat', unit: 'kg', cost: 580, stock: 4.2, minimum: 5 },
    { id: 'ing-5', name: 'Eggs', category: 'Dairy', unit: 'pcs', cost: 9.5, stock: 96, minimum: 60 },
    { id: 'ing-6', name: 'Bacon', category: 'Meat', unit: 'kg', cost: 460, stock: 7.8, minimum: 4 },
    { id: 'ing-7', name: 'Cooking Oil', category: 'Pantry', unit: 'L', cost: 96, stock: 3.4, minimum: 8 },
    { id: 'ing-8', name: 'Parmesan', category: 'Dairy', unit: 'kg', cost: 760, stock: 3.1, minimum: 2 }
  ],
  recipes: [
    { id: 'rec-1', name: 'Pepperoni Pizza', category: 'Main Course', price: 520, wastage: 3, ingredients: [{ ingredientId: 'ing-2', quantity: .25 }, { ingredientId: 'ing-3', quantity: .12 }, { ingredientId: 'ing-1', quantity: .18 }, { ingredientId: 'ing-4', quantity: .08 }] },
    { id: 'rec-2', name: 'Classic Carbonara', category: 'Pasta', price: 390, wastage: 2, ingredients: [{ ingredientId: 'ing-2', quantity: .12 }, { ingredientId: 'ing-5', quantity: 2 }, { ingredientId: 'ing-6', quantity: .06 }, { ingredientId: 'ing-8', quantity: .025 }] },
    { id: 'rec-3', name: 'Bacon Breakfast Bowl', category: 'Breakfast', price: 310, wastage: 2.5, ingredients: [{ ingredientId: 'ing-5', quantity: 2 }, { ingredientId: 'ing-6', quantity: .08 }, { ingredientId: 'ing-7', quantity: .02 }] }
  ],
  inventoryTransactions: [
    { id: 'txn-1', ingredientId: 'ing-1', quantity: 10, unitCost: 420, date: '2026-10-23', type: 'Receiving', note: 'Weekly dairy delivery' },
    { id: 'txn-2', ingredientId: 'ing-2', quantity: 25, unitCost: 68, date: '2026-10-21', type: 'Receiving', note: 'Dry goods delivery' },
    { id: 'txn-3', ingredientId: 'ing-3', quantity: -1.5, unitCost: 145, date: '2026-10-24', type: 'Production', note: 'Kitchen production issue' }
  ],
  productionLogs: [{ id: 'prod-1', recipeId: 'rec-1', quantity: 18, date: '2026-10-24', mode: 'Batch production' }],
  wasteLogs: [{ id: 'waste-1', ingredientId: 'ing-3', quantity: 1.2, reason: 'Spoiled', date: '2026-10-24' }, { id: 'waste-2', ingredientId: 'ing-1', quantity: .45, reason: 'Over-preparation', date: '2026-10-22' }, { id: 'waste-3', ingredientId: 'ing-7', quantity: .8, reason: 'Burned', date: '2026-10-20' }],
  physicalCounts: [{ id: 'count-1', ingredientId: 'ing-1', expected: 12.5, actual: 11.9, date: '2026-10-24' }, { id: 'count-2', ingredientId: 'ing-3', expected: 9, actual: 9.6, date: '2026-10-24' }],
  users: [],
  reservations: [
    { id: 'RS-1042', name: 'Mia Reyes', email: 'mia@email.com', phone: '', date: '2026-10-29', time: '6:00 PM', guests: 2, table: 'T04', status: 'Confirmed', preference: 'Window', request: '' },
    { id: 'RS-1043', name: 'James Miller', email: 'james@email.com', phone: '', date: '2026-10-29', time: '7:30 PM', guests: 4, table: 'T08', status: 'Confirmed', preference: 'Any available table', request: '' },
    { id: 'RS-1044', name: 'Sofia Cruz', email: 'sofia@email.com', phone: '', date: '2026-10-29', time: '7:30 PM', guests: 3, table: 'T02', status: 'Pending', preference: 'Quiet corner', request: '' },
    { id: 'RS-1045', name: 'Noah Garcia', email: 'noah@email.com', phone: '', date: '2026-10-29', time: '8:30 PM', guests: 5, table: 'T10', status: 'Pending', preference: 'Outdoor patio', request: '' },
    { id: 'RS-1046', name: 'Ava Santos', email: 'ava@email.com', phone: '', date: '2026-10-29', time: '11:30 AM', guests: 2, table: 'T01', status: 'Completed', preference: 'Any available table', request: '' },
    { id: 'RS-1047', name: 'Liam Tan', email: 'liam@email.com', phone: '', date: '2026-10-30', time: '6:00 PM', guests: 6, table: 'T12', status: 'Confirmed', preference: 'Window', request: '' }
  ],
  restaurantTables: [
    { id: 'T01', seats: 2, status: 'occupied', x: 18, y: 26, guest: 'Ava Santos' }, { id: 'T02', seats: 4, status: 'reserved', x: 42, y: 26, guest: 'Sofia Cruz' },
    { id: 'T03', seats: 2, status: 'available', x: 66, y: 26 }, { id: 'T04', seats: 2, status: 'reserved', x: 83, y: 26, guest: 'Mia Reyes' },
    { id: 'T05', seats: 4, status: 'available', x: 18, y: 60 }, { id: 'T06', seats: 4, status: 'occupied', x: 42, y: 60, guest: 'Walk-in guest' },
    { id: 'T07', seats: 6, status: 'available', x: 68, y: 61 }, { id: 'T08', seats: 4, status: 'reserved', x: 85, y: 61, guest: 'James Miller' },
    { id: 'T09', seats: 2, status: 'available', x: 28, y: 86 }, { id: 'T10', seats: 6, status: 'reserved', x: 58, y: 86, guest: 'Noah Garcia' }, { id: 'T12', seats: 6, status: 'available', x: 80, y: 86 }
  ]
};
const state = { view: window.location.hash.slice(1) || 'dashboard', role: null, user: null, query: '' };
let modalOpener = null;
let failedPendingId = null;
let passwordRecoveryMode = new URLSearchParams(window.location.hash.slice(1)).get('type') === 'recovery';
let supabaseSyncEnabled = false;
const volatileCollections = new Set(['revenueRecords', 'users']);
const volatileRecords = { revenueRecords: [], users: [] };
const volatilePending = {};
state.ingredientStatus = 'All';
state.ingredientCategory = 'All';
state.ingredientUnit = 'All';
state.recipeCategory = 'All';
state.recipeDraft = [];
state.reservationFilter = 'All';
state.calendarDate = '';
state.revenueRange = '30';
state.revenueStatus = 'Active';
const roleAccess = {
  'Administrator': ['dashboard', 'ingredients', 'receiving', 'recipes', 'production', 'waste', 'counts', 'reports', 'revenue', 'users', 'roles', 'settings', 'reservations', 'calendar'],
  'Manager': ['dashboard', 'ingredients', 'receiving', 'recipes', 'production', 'waste', 'counts', 'reports', 'revenue', 'reservations', 'calendar'],
  'Inventory Clerk': ['ingredients', 'receiving', 'counts'],
  'Chef / Kitchen Staff': ['recipes', 'production', 'waste'],
  'Receptionist': ['dashboard', 'reservations', 'calendar', 'reports']
};
const canAccess = view => Boolean(roleAccess[state.role]?.includes(view));
const canAccessRevenue = () => ['Administrator', 'Manager'].includes(state.role);
const app = document.querySelector('#app');
const money = value => `₱${Number(value || 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const today = () => { const date = new Date(); return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`; };
const read = key => volatileCollections.has(key) ? volatileRecords[key] : JSON.parse(localStorage.getItem(`costtrack_${key}`) || 'null') || [];
function currentUserName() {
  return state.user?.full_name?.trim() || state.user?.email || 'Signed-in user';
}
function currentUserInitials() {
  return currentUserName().split(/[\s@._-]+/).filter(Boolean).slice(0, 2).map(part => part[0].toUpperCase()).join('') || 'U';
}
function dashboardGreeting() {
  const firstName = currentUserName().split(/[\s@._-]+/).filter(Boolean)[0];
  return firstName ? `Good morning, ${esc(firstName)}.` : 'Welcome to CostTrack.';
}
const save = (key, value) => {
  if (key === 'users') {
    toast('User accounts must be managed through Supabase Auth.', 'error');
    return;
  }
  const previous = read(key);
  if (volatileCollections.has(key)) volatileRecords[key] = value;
  else localStorage.setItem(`costtrack_${key}`, JSON.stringify(value));
  if (!window.supabaseRecord || key === 'users') return;
  const oldRecords = new Map(previous.map(record => [String(record.id), record]));
  const newRecords = new Map(value.map(record => [String(record.id), record]));
  const writes = [
    ...[...oldRecords.keys()].filter(recordId => !newRecords.has(recordId)).map(recordId => ({ type: 'remove', id: recordId })),
    ...value.filter(record => JSON.stringify(oldRecords.get(String(record.id))) !== JSON.stringify(record)).map(record => ({ type: 'upsert', record }))
  ];
  if (!writes.length) return;
  queuePendingWrites(key, writes);
  processPendingSync();
};
const all = key => read(key);
const ingredient = id => all('ingredients').find(item => item.id === id);
const recipe = id => all('recipes').find(item => item.id === id);
const id = prefix => `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
function hydrate() {}
function revenueSeed() {
  const records = [];
  for (let offset = 14; offset >= 1; offset -= 1) {
    const date = new Date();
    date.setDate(date.getDate() - offset);
    const businessDate = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    const adults = 38 + (offset % 5) * 4;
    const children = 5 + (offset % 3);
    records.push(createRevenueRecord({ id: `REV-${offset}`, business_date: businessDate, meal_period: offset % 2 ? 'Dinner' : 'All Day', adult_customers: adults, adult_rate: 599, child_customers: children, child_rate: 299, senior_pwd_customers: offset === 7 ? 5 : 0, senior_pwd_rate: 479, remarks: 'Opening revenue seed', recorded_by: 'Administrator', recorded_at: new Date().toISOString() }));
  }
  records.push(createRevenueRecord({ id: 'REV-VOIDED', business_date: records[0].business_date, meal_period: 'Lunch', adult_customers: 2, adult_rate: 599, child_customers: 0, child_rate: 299, senior_pwd_customers: 0, senior_pwd_rate: 479, status: 'Voided', voided_by: 'Administrator', void_reason: 'Seeded void example', recorded_by: 'Administrator', recorded_at: new Date().toISOString() }));
  return records;
}
function createRevenueRecord(data) {
  return window.CostTrackLogic.createRevenueRecord(data);
}
function ensureRevenueSeed() {
  if (!localStorage.getItem('costtrack_revenueRecords')) save('revenueRecords', revenueSeed());
}
function computedRecipeCost(item) { return window.CostTrackLogic.computedRecipeCost(item, all('ingredients')); }
function inventoryValue() { return all('ingredients').reduce((sum, item) => sum + item.stock * item.cost, 0); }
function productionCost(date) { return all('productionLogs').filter(item => !date || item.date === date).reduce((sum, item) => sum + computedRecipeCost(recipe(item.recipeId) || { ingredients: [] }) * Number(item.quantity || 0), 0); }
function wasteCost(date) { return all('wasteLogs').filter(item => !date || item.date === date).reduce((sum, item) => sum + item.quantity * (ingredient(item.ingredientId)?.cost || 0), 0); }
function revenueRecords() { return canAccessRevenue() ? all('revenueRecords') : []; }
function profitability(date, record) {
  const revenue = Number(record?.total_revenue || 0);
  const production = productionCost(date);
  const waste = wasteCost(date);
  const profit = revenue - production - waste;
  return { revenue, production, waste, profit, foodCostPercent: revenue ? production / revenue * 100 : null, wasteCostPercent: revenue ? waste / revenue * 100 : null, profitMargin: revenue ? profit / revenue * 100 : null };
}
function reservationRevenue(item) { return window.CostTrackLogic.reservationRevenue(item); }
function buffetRevenue(date = today()) { return all('reservations').filter(item => item.date === date && item.status !== 'Cancelled' && item.status !== 'No-show').reduce((sum, item) => sum + reservationRevenue(item), 0); }
function lowStock() { return all('ingredients').filter(item => item.stock <= item.minimum); }
function esc(value) { return String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[char])); }
function toast(message, type = 'success') { const root = document.querySelector('#toastRoot'); root.innerHTML = `<div class="toast ${type}">${type === 'success' ? '✓' : '!'} ${esc(message)}</div>`; setTimeout(() => root.innerHTML = '', 3200); }
function setSyncStatus(status, detail = '') {
  const badge = document.querySelector('#syncStatus');
  if (!badge) return;
  const labels = { connected: 'Cloud synced', syncing: 'Syncing…', offline: 'Offline', error: 'Sync failed · Retry' };
  badge.dataset.state = status;
  badge.textContent = status === 'error' && failedPendingId ? 'Sync failed · Resolve' : labels[status] || status;
  badge.title = detail || labels[status] || status;
  badge.setAttribute('aria-label', badge.title);
  const discard = document.querySelector('#discardSyncButton');
  if (discard) discard.classList.toggle('is-hidden', status !== 'error' || !failedPendingId);
}
const sidebarGroups = [
  { id: 'front-of-house', label: 'Front of House', icon: '▣', items: [['reservations', '▤', 'Reservations'], ['calendar', '▦', 'Reservation Calendar']] },
  { id: 'inventory', label: 'Inventory Management', icon: '◈', items: [['ingredients', '◈', 'Ingredients'], ['receiving', '↓', 'Inventory Receiving'], ['counts', '⌗', 'Physical Count']] },
  { id: 'production', label: 'Food Production', icon: '♨', items: [['recipes', '◇', 'Recipes'], ['production', '♨', 'Production Logs'], ['waste', '◌', 'Waste Logs']] },
  { id: 'revenue-management', label: 'Revenue Management', icon: '₱', items: [['revenue', '₱', 'Revenue Tracking']] },
  { id: 'analytics', label: 'Analytics & Reports', icon: '▥', items: [['reports', '▥', 'Inventory Reports'], ['reports', '◒', 'Cost Reports'], ['reports', '◌', 'Waste Reports'], ['reports', '▤', 'Reservation Reports'], ['reports', '⌗', 'Table Utilization Reports'], ['reports', '▦', 'Analytics Dashboard']] },
  { id: 'system', label: 'System Management', icon: '⚙', items: [['users', '♙', 'User Management'], ['users', '⌘', 'Role Management'], ['settings', '⚙', 'System Settings']] }
];
function sidebarGroupState() {
  const saved = localStorage.getItem(`costtrack_sidebar_groups_${state.role}`);
  if (saved) {
    try {
      const groups = JSON.parse(saved);
      if (Array.isArray(groups)) return groups;
    } catch (error) {
      localStorage.removeItem(`costtrack_sidebar_groups_${state.role}`);
    }
  }
  const activeGroup = sidebarGroups.find(group => group.items.some(([view]) => view === state.view))?.id;
  return activeGroup ? [activeGroup] : [];
}
function nav() {
  const openGroups = sidebarGroupState();
  const pending = all('reservations').filter(item => item.status === 'Pending').length;
  const wasteAlerts = all('wasteLogs').filter(item => item.date === today()).length;
  const renderBadge = view => view === 'reservations' && pending ? `<b class="nav-badge" title="${pending} pending reservations" aria-label="${pending} pending reservations">${pending}</b>` : view === 'ingredients' && lowStock().length ? `<b class="nav-badge" title="${lowStock().length} low stock ingredients" aria-label="${lowStock().length} low stock ingredients">${lowStock().length}</b>` : view === 'waste' && wasteAlerts ? `<b class="nav-badge warning-badge" title="${wasteAlerts} waste alerts" aria-label="${wasteAlerts} waste alerts">${wasteAlerts}</b>` : '';
  const groups = sidebarGroups.map(group => {
    const visible = group.items.filter(([view, , label]) => canAccess(view) && !(state.role === 'Receptionist' && group.id === 'analytics' && !['Reservation Reports', 'Table Utilization Reports'].includes(label)));
    if (!visible.length) return '';
    const expanded = openGroups.includes(group.id);
    return `<section class="nav-group ${expanded ? 'is-expanded' : ''}"><button class="nav-group-toggle" type="button" data-action="toggle-nav-group" data-group="${group.id}" aria-expanded="${expanded}" title="${group.label}"><span class="nav-group-icon">${group.icon}</span><span class="nav-group-label">${group.label}</span><span class="nav-group-chevron">⌄</span></button><div class="nav-group-items">${visible.map(([view, icon, label]) => `<button class="nav-item ${state.view === view ? 'active' : ''}" data-view="${view}" title="${label}"><span class="nav-icon">${icon}</span><span class="nav-item-label">${label}</span>${renderBadge(view)}</button>`).join('')}</div></section>`;
  }).join('');
  const overview = canAccess('dashboard') ? `<section class="nav-group overview-group is-expanded"><button class="nav-item overview-item ${state.view === 'dashboard' ? 'active' : ''}" data-view="dashboard" title="Dashboard"><span class="nav-icon">⌂</span><span class="nav-item-label">Dashboard</span></button></section>` : '';
  return `<div class="brand"><div class="brand-mark">CT</div><div class="brand-copy"><strong>COST<span>TRACK</span></strong><small>BOH cost management</small></div><button class="sidebar-collapse" data-action="toggle-sidebar" aria-label="Collapse sidebar" title="Collapse sidebar">‹</button></div><div class="workspace-switcher"><div class="avatar restaurant-avatar">CT</div><div class="workspace-copy"><span>Workspace</span><strong>Back-of-house</strong></div><span class="chevron">⌄</span></div><nav class="sidebar-nav">${overview}${groups}</nav><div class="sidebar-bottom"><div class="help-card"><div class="help-icon">?</div><div><strong>CostTrack guide</strong><span>Learn the workflow</span></div><span class="arrow">→</span></div><div class="user-mini"><div class="avatar user-avatar">${esc(currentUserInitials())}</div><div class="user-copy"><strong>${esc(currentUserName())}</strong><span>${esc(state.role)}</span></div></div></div>`;
}
function saveSidebarGroups(groups) {
  localStorage.setItem(`costtrack_sidebar_groups_${state.role}`, JSON.stringify(groups));
}
function toggleSidebarGroup(groupId) {
  const groups = sidebarGroupState();
  const next = groups.includes(groupId) ? groups.filter(idValue => idValue !== groupId) : [...groups, groupId];
  saveSidebarGroups(next);
  render();
}
function login(message = '') {
  document.querySelector('#appShell').classList.add('is-hidden');
  document.querySelector('#loginScreen').classList.remove('is-hidden');
  const recovering = passwordRecoveryMode || new URLSearchParams(window.location.hash.slice(1)).get('type') === 'recovery';
  document.querySelector('#loginScreen').innerHTML = `<div class="login-card"><div class="login-brand"><div class="brand-mark">CT</div><strong>COST<span>TRACK</span></strong></div><span class="eyebrow">Back-of-house cost management</span><h1>Know your food cost.<br><em>Run a smarter kitchen.</em></h1><p>Track ingredients, recipes, production, waste, and variance in one focused workspace.</p>${message ? `<p class="auth-message" role="alert">${esc(message)}</p>` : ''}${recovering ? `<form id="passwordRecoveryForm"><label>New password<input name="password" type="password" minlength="8" autocomplete="new-password" required></label><button class="primary-btn" type="submit">Update password</button></form>` : `<form id="loginForm"><label>Work email<input name="email" type="email" autocomplete="username" required></label><label>Password<input name="password" type="password" autocomplete="current-password" required></label><button class="primary-btn" type="submit">Sign in to CostTrack <span>→</span></button></form><button class="link-button" id="resetPasswordButton" type="button">Send password reset link</button><small>Accounts are provisioned by your CostTrack administrator.</small>`}</div><div class="login-art"><div><span>Today’s focus</span><strong>Reduce waste.<br>Protect margin.</strong><p>Make every ingredient movement visible from delivery to plate.</p></div><div class="art-stat"><b>${lowStock().length}</b><span>items need attention</span></div></div>`;
}
function metric(label, value, icon, tone, foot) { return `<div class="metric-card"><div class="metric-top"><span>${label}</span><i class="metric-icon ${tone}">${icon}</i></div><div class="metric-value">${value}</div><div class="metric-foot">${foot}</div></div>`; }
function stockStatus(item) { return item.stock <= 0 ? 'Out of Stock' : item.stock <= item.minimum ? 'Low Stock' : 'Healthy'; }
function roleDashboard() {
  const ingredients = all('ingredients');
  const out = ingredients.filter(item => stockStatus(item) === 'Out of Stock').length;
  const low = ingredients.filter(item => stockStatus(item) === 'Low Stock').length;
  const healthy = ingredients.filter(item => stockStatus(item) === 'Healthy').length;
  const recipes = all('recipes');
  const todayDate = today();
  const productionToday = all('productionLogs').filter(item => item.date === todayDate).length;
  const wasteToday = all('wasteLogs').filter(item => item.date === todayDate).length;
  const counts = all('physicalCounts');
  const shortages = counts.filter(item => item.actual < item.expected).length;
  const roleCopy = {
    Administrator: ['System overview', 'Your complete CostTrack workspace at a glance.'],
    Manager: ['Operational summary', 'Monitor cost, stock health, waste, and variance.'],
    'Inventory Clerk': ['Inventory control center', 'Keep supplies accurate, available, and ready for service.'],
    'Chef / Kitchen Staff': ['Kitchen workspace', 'Focus on recipes, production, and waste during today’s shift.'],
    Receptionist: ['Front-of-house workspace', 'Keep reservations, arrivals, and table assignments moving smoothly.']
  };
  const [eyebrow, subtitle] = roleCopy[state.role];
  const reservations = all('reservations');
  const pendingReservations = reservations.filter(item => item.status === 'Pending').length;
  const checkedInReservations = reservations.filter(item => item.status === 'Checked-in').length;
  const revenueToday = canAccessRevenue() ? revenueRecords().filter(item => item.status === 'Active' && item.business_date === todayDate).reduce((sum, item) => sum + item.total_revenue, 0) : 0;
  const profitToday = canAccessRevenue() ? profitability(todayDate, { total_revenue: revenueToday }).profit : 0;
  const foodCostToday = revenueToday ? productionCost(todayDate) / revenueToday * 100 : null;
  const cards = state.role === 'Receptionist'
    ? [metric("Today's reservations", reservations.filter(item => item.date === today()).length, '▤', 'orange-icon', `${pendingReservations} awaiting confirmation`), metric('Guests expected', reservations.filter(item => item.date === today()).reduce((sum, item) => sum + Number(item.guests), 0), '♙', 'green-icon', 'Across today’s bookings'), metric('Checked in', checkedInReservations, '✓', 'purple-icon', 'Guests currently seated'), metric('Open tables', all('restaurantTables').filter(item => item.status === 'available').length, '⌂', 'orange-icon', 'Ready for assignment')]
    : state.role === 'Chef / Kitchen Staff'
    ? [metric('Recipes created', recipes.length, '◇', 'purple-icon', `${new Set(recipes.map(item => item.category)).size} categories`), metric('Production logs today', productionToday, '♨', 'green-icon', 'Batches recorded today'), metric('Waste logs today', wasteToday, '◌', 'red-icon', money(wasteCost()) + ' total waste cost'), metric('Active recipes', recipes.length, '↗', 'orange-icon', 'Available to produce')]
    : state.role === 'Inventory Clerk'
      ? [metric('Out of stock items', out, '!', 'red-icon', 'Immediate replenishment needed'), metric('Low stock items', low, '↓', 'orange-icon', 'Below minimum level'), metric('Healthy stock items', healthy, '✓', 'green-icon', 'At safe stock level'), metric('Total ingredients', ingredients.length, '◈', 'purple-icon', money(inventoryValue()) + ' inventory value')]
      : state.role === 'Manager'
        ? [metric("Today's Revenue", money(revenueToday), '₱', 'green-icon', 'Active buffet entries'), metric('Estimated Profit', money(profitToday), '↗', profitToday >= 0 ? 'green-icon' : 'red-icon', 'Revenue − production − waste'), metric('Food Cost %', foodCostToday === null ? '—' : `${foodCostToday.toFixed(1)}%`, '♨', 'orange-icon', 'Production cost / revenue'), metric('Waste cost', money(wasteCost(todayDate)), '◌', 'red-icon', 'Matched to today')]
        : [metric("Today's Revenue", money(revenueToday), '₱', 'green-icon', 'Active buffet entries'), metric('Estimated Profit', money(profitToday), '↗', profitToday >= 0 ? 'green-icon' : 'red-icon', 'Revenue − production − waste'), metric('Food Cost %', foodCostToday === null ? '—' : `${foodCostToday.toFixed(1)}%`, '♨', 'orange-icon', 'Production cost / revenue'), metric('Low stock items', low + out, '!', 'red-icon', 'Needs attention')];
  const recipeCategories = [...new Set(recipes.map(item => item.category))];
  const kitchenPanel = `<div class="panel"><div class="panel-header"><div><div class="panel-title">Kitchen activity</div><div class="panel-subtitle">Recently used recipes and categories</div></div><button class="text-btn" data-view="recipes">Open recipes →</button></div><div class="dashboard-list">${recipes.slice(0, 5).map(item => `<div class="dashboard-list-row"><span class="recipe-icon">◇</span><div><strong>${esc(item.name)}</strong><small>${esc(item.category)} · ${item.ingredients.length} ingredients</small></div><span class="tag">${money(computedRecipeCost(item))} / serving</span></div>`).join('')}</div><div class="category-chips">${recipeCategories.map(item => `<span>${esc(item)}</span>`).join('')}</div></div>`;
  const inventoryPanel = `<div class="panel inventory-health-panel"><div class="panel-header"><div><div class="panel-title">Inventory health</div><div class="panel-subtitle">Filter stock levels for quick action</div></div><button class="text-btn" data-view="ingredients">Manage inventory →</button></div><div class="quick-filters">${['All', 'Out of Stock', 'Low Stock', 'Healthy'].map(item => `<button class="${state.ingredientStatus === item ? 'active' : ''}" data-dashboard-status="${item}">${item}<b>${item === 'All' ? ingredients.length : ingredients.filter(x => stockStatus(x) === item).length}</b></button>`).join('')}</div><div class="dashboard-list">${ingredients.filter(item => state.ingredientStatus === 'All' || stockStatus(item) === state.ingredientStatus).slice(0, 6).map(item => `<div class="dashboard-list-row"><span class="ingredient-dot">${item.name[0]}</span><div><strong>${esc(item.name)}</strong><small>${item.stock} ${item.unit} · minimum ${item.minimum}</small></div><span class="status ${stockStatus(item) === 'Healthy' ? 'status-good' : 'status-low'}">${stockStatus(item)}</span></div>`).join('')}</div></div>`;
  const charts = `<div class="dashboard-grid dashboard-charts"><div class="panel"><div class="panel-title">Food cost trend</div><div class="panel-subtitle">Monthly cost movement</div><div class="chart-wrap"><svg class="chart-svg" viewBox="0 0 700 230" preserveAspectRatio="none"><path d="M0 185 C80 175 92 130 160 145 S260 100 330 122 S430 70 495 92 S600 35 700 55" fill="none" stroke="#168277" stroke-width="3"/><path d="M0 205 C95 198 110 170 180 181 S280 160 350 170 S440 132 505 151 S610 116 700 126" fill="none" stroke="#e99751" stroke-width="2" stroke-dasharray="5 5"/><g class="chart-axis">${['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'].map((x, i) => `<text x="${i * 140 + 5}" y="220">${x}</text>`).join('')}</g></svg></div><div class="legend"><span class="sales">Food cost</span><span class="profit">Margin trend</span></div></div><div class="panel"><div class="panel-title">Cost analytics</div><div class="panel-subtitle">Current operational indicators</div><div class="analytics-stack"><div><span>Inventory value</span><strong>${money(inventoryValue())}</strong></div><div><span>Waste cost</span><strong>${money(wasteCost())}</strong></div><div><span>Variance flags</span><strong>${shortages}</strong></div></div></div></div>`;
  const reservationPanel = `<div class="panel reservation-summary-panel"><div class="panel-header"><div><div class="panel-title">Reservation service</div><div class="panel-subtitle">${pendingReservations} bookings need attention · ${reservations.filter(item => item.date === today()).length} today</div></div><button class="text-btn" data-view="reservations">Manage reservations →</button></div><div class="dashboard-list">${reservations.filter(item => item.date === today()).slice(0, 4).map(item => `<div class="dashboard-list-row"><span class="ingredient-dot">${esc(item.name.charAt(0))}</span><div><strong>${esc(item.name)}</strong><small>${esc(item.time)} · ${item.guests} guests · ${esc(item.table || 'Unassigned')}</small></div><span class="status">${esc(item.status)}</span></div>`).join('') || '<p class="panel-subtitle">No reservations scheduled for today.</p>'}</div></div>`;
  return `<div class="welcome-row"><div><div class="eyebrow">${eyebrow}</div><h1>${dashboardGreeting()}</h1><p>${subtitle}</p></div>${state.role === 'Receptionist' ? '<button class="primary-btn" data-action="open-reservation">+ New reservation</button>' : state.role === 'Inventory Clerk' || state.role === 'Administrator' || state.role === 'Manager' ? '<button class="primary-btn" data-action="open-receiving">+ Receive inventory</button>' : '<button class="primary-btn" data-action="open-production">+ Log production</button>'}</div><div class="metric-grid role-metric-grid">${cards.join('')}</div>${state.role === 'Receptionist' ? `<div class="dashboard-grid">${reservationPanel}<div class="panel"><div class="panel-title">Front-of-house checklist</div><div class="checklist"><span>✓ Confirm pending bookings</span><span>○ Check in arriving guests</span><span>○ Review table assignments</span></div></div></div>` : state.role === 'Chef / Kitchen Staff' ? `<div class="dashboard-grid">${kitchenPanel}<div class="panel"><div class="panel-title">Today’s kitchen checklist</div><div class="checklist"><span>✓ Review active recipe cards</span><span>✓ Record completed batches</span><span>○ Log waste before end of shift</span></div></div></div>` : state.role === 'Inventory Clerk' ? inventoryPanel : state.role === 'Manager' ? `<div class="dashboard-grid">${inventoryPanel}${reservationPanel}</div>` : `<div class="dashboard-grid">${reservationPanel}${inventoryPanel}</div>`}${state.role === 'Chef / Kitchen Staff' ? '' : charts}`;
}
function dashboard() {
  const recipes = all('recipes'); const profit = recipes.reduce((sum, item) => sum + (item.price - computedRecipeCost(item)), 0) / (recipes.length || 1); const margin = recipes.reduce((sum, item) => sum + ((item.price - computedRecipeCost(item)) / item.price * 100), 0) / (recipes.length || 1);
  return `<div class="welcome-row"><div><div class="eyebrow">Saturday, October 24, 2026</div><h1>${dashboardGreeting()}</h1><p>Here’s what’s happening in your kitchen today.</p></div><button class="primary-btn" data-action="open-receiving">+ Receive inventory</button></div><div class="metric-grid">${metric('Total inventory value', money(inventoryValue()), '◈', 'green-icon', '<span class="up">↑ 4.8%</span> vs last month')}${metric('Total ingredients', all('ingredients').length, '⌘', 'purple-icon', `${lowStock().length} require attention`)}${metric('Recipe cost margin', `${margin.toFixed(1)}%`, '↗', 'orange-icon', `${money(profit)} avg. profit / recipe`)}${metric('Waste cost · October', money(wasteCost()), '◌', 'red-icon', '<span class="down">↓ 12.4%</span> vs last month')}</div><div class="dashboard-grid"><div class="panel"><div class="panel-header"><div><div class="panel-title">Food cost overview</div><div class="panel-subtitle">Monthly recipe revenue, cost, and margin</div></div><select class="select-small"><option>Last 6 months</option></select></div><div class="chart-wrap"><svg class="chart-svg" viewBox="0 0 700 230" preserveAspectRatio="none"><defs><linearGradient id="fill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#168277" stop-opacity=".22"/><stop offset="1" stop-color="#168277" stop-opacity="0"/></linearGradient></defs><path d="M0 185 C80 175 92 130 160 145 S260 100 330 122 S430 70 495 92 S600 35 700 55 L700 230 L0 230Z" fill="url(#fill)"/><path d="M0 185 C80 175 92 130 160 145 S260 100 330 122 S430 70 495 92 S600 35 700 55" fill="none" stroke="#168277" stroke-width="3"/><path d="M0 205 C95 198 110 170 180 181 S280 160 350 170 S440 132 505 151 S610 116 700 126" fill="none" stroke="#e99751" stroke-width="2" stroke-dasharray="5 5"/><g class="chart-axis">${['May','Jun','Jul','Aug','Sep','Oct'].map((x,i) => `<text x="${i * 140 + 5}" y="220">${x}</text>`).join('')}</g></svg></div><div class="legend"><span class="sales">Revenue</span><span class="cost">Recipe cost</span><span class="profit">Margin trend</span></div></div><div class="panel"><div class="panel-header"><div><div class="panel-title">Top profitable recipes</div><div class="panel-subtitle">Based on current ingredient costs</div></div><button class="text-btn" data-view="recipes">View all →</button></div><div class="insight-list">${recipes.slice().sort((a,b) => (b.price - computedRecipeCost(b)) - (a.price - computedRecipeCost(a))).map(item => `<div class="insight-item"><div class="dish-thumb">${item.name.includes('Pizza') ? '🍕' : item.name.includes('Carbonara') ? '🍝' : '🥣'}</div><div class="insight-copy"><strong>${esc(item.name)}</strong><span>${((item.price - computedRecipeCost(item)) / item.price * 100).toFixed(1)}% margin</span></div><div class="profit-amount">${money(item.price - computedRecipeCost(item))}<small>per serving</small></div></div>`).join('')}</div></div></div><div class="bottom-grid"><div class="panel"><div class="panel-header"><div><div class="panel-title">Inventory health</div><div class="panel-subtitle">Items closest to minimum stock</div></div><button class="text-btn" data-view="ingredients">Manage inventory →</button></div>${all('ingredients').slice().sort((a,b) => a.stock / a.minimum - b.stock / b.minimum).slice(0, 4).map(item => `<div class="stock-row"><div class="stock-name"><span class="ingredient-dot">${item.name[0]}</span><div><strong>${esc(item.name)}</strong><small>${item.stock} ${item.unit} of ${item.minimum} minimum</small></div></div><div class="stock-bar"><i style="width:${Math.min(100, item.stock / item.minimum * 100)}%" class="${item.stock <= item.minimum ? 'danger' : ''}"></i></div><span class="stock-state ${item.stock <= item.minimum ? 'low' : 'healthy'}">${item.stock <= item.minimum ? 'Low stock' : 'Healthy'}</span></div>`).join('')}</div><div class="panel"><div class="panel-header"><div><div class="panel-title">Recent activity</div><div class="panel-subtitle">Latest kitchen movements</div></div><button class="text-btn" data-view="reports">Reports →</button></div><div class="activity-list">${sales.slice(-3).reverse().map(item => `<div><span class="activity-icon production">♨</span><p><strong>${recipe(item.recipeId)?.name || 'Recipe'}</strong> <span>· ${item.quantity} servings recorded</span><small>${item.date}</small></p></div>`).join('')}</div></div></div>`;
}
function pageHeader(eyebrow, title, subtitle, action = '') { return `<div class="page-header"><div><div class="eyebrow">${eyebrow}</div><h1>${title}</h1><p>${subtitle}</p></div>${action}</div>`; }
function tablePage(config) { return `${pageHeader(config.eyebrow, config.title, config.subtitle, config.action)}<div class="toolbar"><div class="search-box">⌕<input id="tableSearch" placeholder="Search ${config.search || 'records'}..." value="${esc(state.query)}"></div>${config.filters || ''}<span class="record-count">${config.rows.length} records</span></div><div class="panel table-panel"><div class="table-scroll"><table><thead><tr>${config.headers.map(item => `<th>${item}</th>`).join('')}</tr></thead><tbody>${config.rows.length ? config.rows.join('') : `<tr><td colspan="${config.headers.length}" class="empty-state">No records found. Add your first record to get started.</td></tr>`}</tbody></table></div></div>`; }
function ingredientsPage() { const rows = all('ingredients').filter(x => `${x.name} ${x.category}`.toLowerCase().includes(state.query.toLowerCase())).map(item => `<tr><td><div class="cell-title"><span class="ingredient-dot">${item.name[0]}</span><strong>${esc(item.name)}</strong></div></td><td><span class="tag">${esc(item.category)}</span></td><td>${item.unit}</td><td>${money(item.cost)}</td><td><strong>${item.stock}</strong> ${item.unit}</td><td><span class="status ${item.stock <= item.minimum ? 'status-low' : 'status-good'}">${item.stock <= item.minimum ? 'Low stock' : 'Healthy'}</span><small class="sub-cell">Min. ${item.minimum} ${item.unit}</small></td><td>${actions('ingredient', item.id)}</td></tr>`); return tablePage({ eyebrow: 'Master data', title: 'Ingredients', subtitle: 'Manage ingredient costs, stock levels, and reorder thresholds.', action: `<button class="primary-btn" data-action="open-ingredient">+ Add ingredient</button>`, search: 'ingredients', headers: ['Ingredient', 'Category', 'Unit', 'Cost / unit', 'Current stock', 'Stock health', ''], rows }); }
function receivingPage() { const rows = all('inventoryTransactions').slice().reverse().filter(x => `${ingredient(x.ingredientId)?.name} ${x.note}`.toLowerCase().includes(state.query.toLowerCase())).map(item => `<tr><td><strong>${esc(ingredient(item.ingredientId)?.name || 'Unknown')}</strong><small class="sub-cell">${esc(item.note || 'Inventory movement')}</small></td><td><span class="status ${item.quantity > 0 ? 'status-good' : 'status-low'}">${item.quantity > 0 ? 'Received' : 'Issued'}</span></td><td class="${item.quantity > 0 ? 'positive' : 'negative'}">${item.quantity > 0 ? '+' : ''}${item.quantity} ${ingredient(item.ingredientId)?.unit || ''}</td><td>${money(item.unitCost)}</td><td>${item.date}</td><td>${actions('transaction', item.id)}</td></tr>`); return tablePage({ eyebrow: 'Inventory movement', title: 'Inventory receiving', subtitle: 'Receive supplies and keep every stock movement traceable.', action: `<button class="primary-btn" data-action="open-receiving">+ Receive supplies</button>`, search: 'transactions', headers: ['Ingredient', 'Movement', 'Quantity', 'Unit cost', 'Date received', ''], rows }); }
function recipesPage() { const rows = all('recipes').filter(x => x.name.toLowerCase().includes(state.query.toLowerCase())).map(item => { const cost = computedRecipeCost(item); return `<tr><td><div class="cell-title"><span class="recipe-icon">◇</span><strong>${esc(item.name)}</strong></div><small class="sub-cell">${esc(item.category)}</small></td><td>${item.ingredients.length} ingredients</td><td>${money(cost)}</td><td>${money(item.price)}</td><td class="positive">${money(item.price - cost)}</td><td><strong>${((item.price - cost) / item.price * 100).toFixed(1)}%</strong></td><td>${actions('recipe', item.id)}</td></tr>`; }); return tablePage({ eyebrow: 'Cost engineering', title: 'Recipes', subtitle: 'Build recipe cards and monitor serving cost, margin, and wastage.', action: `<button class="primary-btn" data-action="open-recipe">+ Create recipe</button>`, search: 'recipes', headers: ['Recipe', 'Composition', 'Cost / serving', 'Selling price', 'Profit', 'Margin', ''], rows }); }
function logsPage(type) { const isWaste = type === 'waste'; const data = all(isWaste ? 'wasteLogs' : 'productionLogs'); const rows = data.slice().reverse().filter(x => `${ingredient(x.ingredientId)?.name || recipe(x.recipeId)?.name} ${x.reason || ''}`.toLowerCase().includes(state.query.toLowerCase())).map(item => isWaste ? `<tr><td><strong>${esc(ingredient(item.ingredientId)?.name || 'Unknown')}</strong></td><td>${item.quantity} ${ingredient(item.ingredientId)?.unit || ''}</td><td><span class="tag">${esc(item.reason)}</span></td><td>${money(item.quantity * (ingredient(item.ingredientId)?.cost || 0))}</td><td>${item.date}</td><td>${actions('waste', item.id)}</td></tr>` : `<tr><td><strong>${esc(recipe(item.recipeId)?.name || 'Unknown')}</strong></td><td>${item.quantity} servings</td><td><span class="tag">${esc(item.mode)}</span></td><td>${item.date}</td><td>${actions('production', item.id)}</td></tr>`); return tablePage({ eyebrow: 'Kitchen operations', title: isWaste ? 'Waste logs' : 'Production logs', subtitle: isWaste ? 'Understand the cost and causes behind kitchen waste.' : 'Track batch production and recipe usage in the kitchen.', action: `<button class="primary-btn" data-action="open-${isWaste ? 'waste' : 'production'}">+ Log ${isWaste ? 'waste' : 'production'}</button>`, search: 'logs', headers: isWaste ? ['Ingredient', 'Quantity', 'Reason', 'Waste cost', 'Date', ''] : ['Recipe', 'Output', 'Mode', 'Date', ''], rows }); }
function countsPage() { const rows = all('physicalCounts').slice().reverse().map(item => { const diff = item.actual - item.expected; return `<tr><td><strong>${esc(ingredient(item.ingredientId)?.name || 'Unknown')}</strong></td><td>${item.expected} ${ingredient(item.ingredientId)?.unit || ''}</td><td>${item.actual} ${ingredient(item.ingredientId)?.unit || ''}</td><td class="${diff < 0 ? 'negative' : 'positive'}">${diff > 0 ? '+' : ''}${diff.toFixed(2)}</td><td><span class="status ${diff < 0 ? 'status-low' : 'status-good'}">${diff < 0 ? 'Shortage' : 'Overage'}</span></td><td>${item.date}</td><td>${actions('count', item.id)}</td></tr>`; }); return tablePage({ eyebrow: 'Reconciliation', title: 'Physical inventory count', subtitle: 'Compare expected system stock with what is physically on hand.', action: `<button class="primary-btn" data-action="open-count">+ Record count</button>`, search: 'counts', headers: ['Ingredient', 'Expected', 'Actual count', 'Variance', 'Result', 'Count date', ''], rows }); }
function reportsPage() { const ingredients = all('ingredients'); return `${pageHeader('Management insight', 'Reports & analytics', 'Turn operational data into decisions for your next kitchen shift.', `<button class="ghost-btn" onclick="window.print()">Export report ↗</button>`)}<div class="report-grid"><div class="panel report-card"><div class="panel-title">Inventory valuation</div><div class="report-big">${money(inventoryValue())}</div><p>Current value across ${ingredients.length} tracked ingredients</p><div class="mini-bars">${ingredients.slice(0, 6).map(item => `<div><span style="height:${Math.min(100, item.stock * item.cost / 40)}%"></span><small>${item.name.split(' ')[0]}</small></div>`).join('')}</div></div><div class="panel report-card"><div class="panel-title">Waste performance</div><div class="report-big">${money(wasteCost())}</div><p>Total recorded waste cost this month</p><div class="progress-line"><i style="width:${Math.min(100, wasteCost() / 20)}%"></i></div><small class="up">12.4% lower than previous month</small></div><div class="panel report-card"><div class="panel-title">Variance snapshot</div><div class="report-big">${all('physicalCounts').filter(x => x.actual < x.expected).length}<span class="muted-big"> shortages</span></div><p>Across ${all('physicalCounts').length} completed counts</p><div class="variance-list">${all('physicalCounts').map(x => `<span>${esc(ingredient(x.ingredientId)?.name)} <b class="${x.actual < x.expected ? 'negative' : 'positive'}">${(x.actual - x.expected).toFixed(2)}</b></span>`).join('')}</div></div></div><div class="report-tables"><div class="panel"><div class="panel-header"><div><div class="panel-title">Recipe cost report</div><div class="panel-subtitle">Cost per serving and profitability overview</div></div></div><table><thead><tr><th>Recipe</th><th>Cost</th><th>Price</th><th>Food cost %</th><th>Margin</th></tr></thead><tbody>${all('recipes').map(x => { const cost = computedRecipeCost(x); return `<tr><td><strong>${esc(x.name)}</strong></td><td>${money(cost)}</td><td>${money(x.price)}</td><td>${(cost / x.price * 100).toFixed(1)}%</td><td class="positive">${money(x.price - cost)}</td></tr>`; }).join('')}</tbody></table></div></div>`; }
function usersPage() { const rows = all('users').map(item => `<tr><td><div class="cell-title"><span class="avatar user-avatar">${esc((item.name || item.email || '?').split(' ').map(x => x[0]).join('').slice(0, 2))}</span><strong>${esc(item.name || 'Team member')}</strong></div></td><td>${esc(item.email)}</td><td><span class="tag">${esc(item.role)}</span></td><td><span class="status status-good">Active</span></td><td></td></tr>`); return tablePage({ eyebrow: 'Administration', title: 'User management', subtitle: 'Roles come from protected Supabase profiles. Create Auth accounts and profiles through the documented admin setup; browser-side role changes are disabled.', search: 'users', headers: ['User', 'Email', 'Role', 'Status', ''], rows }); }
function ingredientCardsPage() {
  const ingredients = all('ingredients');
  const categories = [...new Set(ingredients.map(item => item.category))];
  const units = [...new Set(ingredients.map(item => item.unit))];
  const filtered = ingredients.filter(item => {
    const queryMatch = `${item.name} ${item.category}`.toLowerCase().includes(state.query.toLowerCase());
    return queryMatch && (state.ingredientCategory === 'All' || item.category === state.ingredientCategory) && (state.ingredientUnit === 'All' || item.unit === state.ingredientUnit) && (state.ingredientStatus === 'All' || stockStatus(item) === state.ingredientStatus);
  });
  return `${pageHeader('Master data', 'Ingredients', 'Manage ingredient costs, stock levels, and reorder thresholds.', '<button class="primary-btn" data-action="open-ingredient">+ Add ingredient</button>')}<div class="catalog-toolbar"><div class="search-box">⌕<input id="tableSearch" placeholder="Search ingredients or categories..." value="${esc(state.query)}"></div><select data-filter="ingredientCategory"><option>All categories</option>${categories.map(item => `<option ${state.ingredientCategory === item ? 'selected' : ''}>${esc(item)}</option>`).join('')}</select><select data-filter="ingredientStatus"><option>All stock status</option>${['Out of Stock', 'Low Stock', 'Healthy'].map(item => `<option ${state.ingredientStatus === item ? 'selected' : ''}>${item}</option>`).join('')}</select><select data-filter="ingredientUnit"><option>All units</option>${units.map(item => `<option ${state.ingredientUnit === item ? 'selected' : ''}>${esc(item)}</option>`).join('')}</select><span class="record-count">${filtered.length} ingredients</span></div><div class="ingredient-card-grid">${filtered.length ? filtered.map(item => `<article class="catalog-card"><div class="catalog-card-top"><span class="ingredient-dot large-dot">${item.name[0]}</span><span class="status ${stockStatus(item) === 'Healthy' ? 'status-good' : 'status-low'}">${stockStatus(item)}</span></div><h3>${esc(item.name)}</h3><span class="tag">${esc(item.category)}</span><div class="catalog-stat"><div><small>Current stock</small><strong>${item.stock} <em>${item.unit}</em></strong></div><div><small>Cost / unit</small><strong>${money(item.cost)}</strong></div></div><div class="catalog-card-footer"><span>Minimum ${item.minimum} ${item.unit}</span><div class="card-actions">${actions('ingredient', item.id)}</div></div></article>`).join('') : '<div class="panel empty-state">No ingredients match these filters.</div>'}</div>`;
}
function recipeCardsPage() {
  const recipes = all('recipes');
  const categories = [...new Set(recipes.map(item => item.category))];
  const filtered = recipes.filter(item => item.name.toLowerCase().includes(state.query.toLowerCase()) && (state.recipeCategory === 'All' || item.category === state.recipeCategory));
  return `${pageHeader('Cost engineering', 'Recipes', 'Build recipe cards and monitor serving cost, margin, and wastage.', '<button class="primary-btn" data-action="open-recipe">+ Create recipe</button>')}<div class="catalog-toolbar"><div class="search-box">⌕<input id="tableSearch" placeholder="Search recipes..." value="${esc(state.query)}"></div><div class="category-tabs"><button class="${state.recipeCategory === 'All' ? 'active' : ''}" data-recipe-category="All">All</button>${categories.map(item => `<button class="${state.recipeCategory === item ? 'active' : ''}" data-recipe-category="${esc(item)}">${esc(item)}</button>`).join('')}</div><span class="record-count">${filtered.length} recipes</span></div><div class="recipe-card-grid">${filtered.length ? filtered.map(item => { const cost = computedRecipeCost(item); return `<article class="catalog-card recipe-card"><div class="catalog-card-top"><span class="recipe-icon large-dot">◇</span><span class="tag">${esc(item.category)}</span></div><h3>${esc(item.name)}</h3><div class="recipe-metrics"><div><small>Cost / serving</small><strong>${money(cost)}</strong></div><div><small>Selling price</small><strong>${money(item.price)}</strong></div><div><small>Margin</small><strong class="positive">${((item.price - cost) / item.price * 100).toFixed(1)}%</strong></div></div><div class="catalog-card-footer"><span>${item.ingredients.length} ingredients</span><div class="card-actions">${actions('recipe', item.id)}</div></div></article>`; }).join('') : '<div class="panel empty-state">No recipes match this category.</div>'}</div>`;
}
function actions(type, itemId) { const editable = ['ingredient', 'recipe', 'user'].includes(type); return `<div class="row-actions">${editable ? `<button data-action="view-${type}" data-id="${itemId}" aria-label="View">◉</button><button data-action="edit-${type}" data-id="${itemId}" aria-label="Edit">✎</button>` : ''}<button class="danger-action" data-action="delete-${type}" data-id="${itemId}" aria-label="Delete">×</button></div>`; }
function options(items, valueKey = 'id', labelKey = 'name') { return items.map(x => `<option value="${x[valueKey]}">${esc(x[labelKey])}</option>`).join(''); }
function openForm(type, item) {
  const edit = item ? true : false; const value = key => item?.[key] ?? '';
  if (type === 'ingredient') modal(edit ? 'Edit ingredient' : 'Add ingredient', `<div class="form-grid"><label>Ingredient name<input name="name" value="${esc(value('name'))}" required></label><label>Category<select name="category"><option>Dairy</option><option>Dry Goods</option><option>Meat</option><option>Produce</option><option>Sauces</option><option>Pantry</option></select></label><label>Unit<select name="unit"><option>kg</option><option>L</option><option>pcs</option><option>box</option></select></label><label>Cost per unit<input name="cost" type="number" min="0.01" step=".01" value="${value('cost')}" required></label>${edit ? `<label>Current stock<input value="${value('stock')}" readonly><small class="field-help">Use Physical Count to update stock.</small></label>` : `<label>Starting stock<input name="stock" type="number" min="0" step=".01" value="0" required></label>`}<label>Minimum stock<input name="minimum" type="number" min="0" step=".01" value="${value('minimum')}" required></label></div>`, 'Save ingredient');
  else if (type === 'receiving') modal('Receive supplies', `<div class="form-grid"><label>Ingredient<select name="ingredientId" required>${options(all('ingredients'))}</select></label><label>Quantity received<input name="quantity" type="number" min=".01" step=".01" required></label><label>Unit cost<input name="unitCost" type="number" min=".01" step=".01" required></label><label>Date received<input name="date" type="date" value="${today()}" required></label><label class="full">Delivery note<input name="note" placeholder="Supplier or delivery reference"></label></div>`);
  else if (type === 'recipe') modal(edit ? 'Edit recipe' : 'Create recipe', `<div class="form-grid"><label>Recipe name<input name="name" value="${esc(value('name'))}" required></label><label>Category<input name="category" value="${esc(value('category') || 'Main Course')}" required></label><label>Selling price<input name="price" type="number" min=".01" step=".01" value="${value('price')}" required></label><label>Wastage percentage<input name="wastage" type="number" min="0" max="100" step=".1" value="${value('wastage') || 2}" required></label><label class="full">Ingredients <small class="field-hint">Enter one ingredient quantity per line: ingredient name | quantity</small><textarea name="composition" required>${(item?.ingredients || []).map(x => `${ingredient(x.ingredientId)?.name || ''} | ${x.quantity}`).join('\n')}</textarea></label></div>`, 'Save recipe');
  else if (type === 'waste') modal('Log kitchen waste', `<div class="form-grid"><label>Ingredient<select name="ingredientId" required>${options(all('ingredients'))}</select></label><label>Quantity wasted<input name="quantity" type="number" min=".01" step=".01" required></label><label>Reason<select name="reason"><option>Expired</option><option>Spoiled</option><option>Burned</option><option>Over-preparation</option><option>Spillage</option></select></label><label>Date<input name="date" type="date" value="${today()}" required></label></div>`);
  else if (type === 'production') modal('Log production batch', `<div class="form-grid"><label>Recipe<select name="recipeId" required>${options(all('recipes'))}</select></label><label>Output quantity<input name="quantity" type="number" min="1" step="1" required></label><label>Mode<select name="mode"><option>Batch production</option><option>End-of-day sales summary</option></select></label><label>Date<input name="date" type="date" value="${today()}" required></label></div>`);
  else if (type === 'count') modal('Record physical count', `<div class="form-grid"><label>Ingredient<select name="ingredientId" required>${options(all('ingredients'))}</select></label><label>Expected quantity<input name="expected" type="number" min="0" step=".01" required></label><label>Actual count<input name="actual" type="number" min="0" step=".01" required></label><label>Count date<input name="date" type="date" value="${today()}" required></label></div>`);
  else if (type === 'user') modal('Add workspace user', `<div class="form-grid"><label>Full name<input name="name" required></label><label>Work email<input name="email" type="email" required></label><label class="full">Role<select name="role"><option>Administrator</option><option>Manager</option><option>Inventory Clerk</option><option>Chef / Kitchen Staff</option><option>Receptionist</option></select></label></div>`, 'Add user');
  document.querySelector('#modalForm').dataset.type = type; if (item) document.querySelector('#modalForm').dataset.id = item.id;
}
function renderRecipeModal() {
  const form = state.recipeForm || {};
  const names = state.recipeDraft.map(item => `${ingredient(item.ingredientId)?.name || 'Ingredient'} | ${item.quantity} ${ingredient(item.ingredientId)?.unit || ''}`);
  modal(form.id ? 'Edit recipe' : 'Create recipe', `<div class="form-grid"><label>Recipe name<input name="name" value="${esc(form.name || '')}" required></label><label>Category<select name="category"><option ${form.category === 'Main Course' ? 'selected' : ''}>Main Course</option><option ${form.category === 'Appetizer' ? 'selected' : ''}>Appetizer</option><option ${form.category === 'Dessert' ? 'selected' : ''}>Dessert</option><option ${form.category === 'Beverage' ? 'selected' : ''}>Beverage</option><option ${form.category === 'Side Dish' ? 'selected' : ''}>Side Dish</option><option ${form.category === 'Sauce' ? 'selected' : ''}>Sauce</option></select></label><label>Selling price<input name="price" type="number" min=".01" step=".01" value="${form.price || ''}" required></label><label>Wastage percentage<input name="wastage" type="number" min="0" max="100" step=".1" value="${form.wastage || 2}" required></label><div class="full recipe-ingredients-field"><div class="field-label">Recipe ingredients <small class="field-hint">Select ingredients from current inventory so every recipe stays linked to stock.</small></div><div class="selected-ingredients">${state.recipeDraft.length ? state.recipeDraft.map((item, index) => `<div class="selected-ingredient"><span>✓</span><strong>${esc(ingredient(item.ingredientId)?.name)}</strong><small>${item.quantity} ${esc(ingredient(item.ingredientId)?.unit || '')}</small><button type="button" data-action="remove-recipe-ingredient" data-index="${index}">×</button></div>`).join('') : '<div class="empty-ingredient">No ingredients added yet.</div>'}</div><button type="button" class="ghost-btn add-ingredient-btn" data-action="toggle-recipe-picker">+ Add Ingredient</button><div class="recipe-picker is-hidden"><label>Inventory ingredient<select name="draftIngredient">${options(all('ingredients'))}</select></label><label>Quantity required<input name="draftQuantity" type="number" min=".001" step=".001" placeholder="e.g. 0.25"></label><button type="button" class="primary-btn compact-btn" data-action="add-recipe-ingredient">Add to recipe</button></div><input type="hidden" name="composition" value="${esc(names.join('\\n'))}"></div></div>`, 'Save recipe');
  document.querySelector('#modalForm').dataset.type = 'recipe';
  if (form.id) document.querySelector('#modalForm').dataset.id = form.id;
}
function openRecipeForm(item) {
  state.recipeDraft = item ? item.ingredients.map(line => ({ ...line })) : [];
  state.recipeForm = item ? { ...item } : {};
  renderRecipeModal();
}
function viewRecord(type, item) {
  if (type === 'ingredient') modal(item.name, `<div class="detail-grid"><div><small>Category</small><strong>${esc(item.category)}</strong></div><div><small>Stock status</small><strong>${stockStatus(item)}</strong></div><div><small>Current stock</small><strong>${item.stock} ${esc(item.unit)}</strong></div><div><small>Cost per unit</small><strong>${money(item.cost)}</strong></div><div><small>Minimum stock</small><strong>${item.minimum} ${esc(item.unit)}</strong></div></div>`, null);
  if (type === 'recipe') { const cost = computedRecipeCost(item); modal(item.name, `<div class="detail-grid"><div><small>Category</small><strong>${esc(item.category)}</strong></div><div><small>Cost per serving</small><strong>${money(cost)}</strong></div><div><small>Selling price</small><strong>${money(item.price)}</strong></div><div><small>Profit margin</small><strong>${((item.price - cost) / item.price * 100).toFixed(1)}%</strong></div><div class="full"><small>Ingredients</small><strong>${item.ingredients.map(line => `${esc(ingredient(line.ingredientId)?.name)} · ${line.quantity} ${esc(ingredient(line.ingredientId)?.unit || '')}`).join('<br>')}</strong></div></div>`, null); }
}
function reservationDateLabel(value) {
  return value ? new Date(`${value}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '—';
}
function reservationStatusClass(status) {
  return ['Confirmed', 'Checked-in', 'Seated', 'Completed'].includes(status) ? 'status-good' : ['Cancelled', 'No-show'].includes(status) ? 'status-out' : 'status-low';
}
function reservationCard(item, showRevenue = false) {
  const guestCount = item.guests || (Number(item.adults || 0) + Number(item.children || 0));
  const details = `<span class="status ${reservationStatusClass(item.status)}">${esc(item.status)}</span><b>${esc(item.name)}</b><small>${guestCount} guests · ${esc(item.table || 'Unassigned')}</small>${showRevenue && canAccessRevenue() ? `<em>${money(item.estimatedRevenue || ((item.adults || item.guests) * 599 + (item.children || 0) * 299))} estimated buffet revenue</em>` : ''}`;
  return `<article class="reservation-card"><button type="button" class="reservation-card-main" data-action="edit-reservation" data-id="${esc(item.id)}" aria-label="View reservation for ${esc(item.name)}">${details}</button>${item.status === 'Pending' ? `<button type="button" class="reservation-confirm-btn" data-action="confirm-reservation" data-id="${esc(item.id)}" aria-label="Confirm reservation for ${esc(item.name)}">Confirm</button>` : ''}</article>`;
}
function reservationForm(item = {}) {
  const tableOptions = all('restaurantTables').map(table => `<option value="${table.id}" ${item.table === table.id ? 'selected' : ''}>${table.id} · ${table.seats} seats</option>`).join('');
  const adults = Number(item.adults || item.guests || 2);
  const children = Number(item.children || 0);
  modal(item.id ? 'Update reservation' : 'New reservation', `<input type="hidden" name="id" value="${esc(item.id || '')}"><label>Guest name<input name="name" value="${esc(item.name || '')}" required autocomplete="name"></label><div class="form-grid"><label>Email<input name="email" type="email" value="${esc(item.email || '')}" required autocomplete="email"></label><label>Phone<input name="phone" value="${esc(item.phone || '')}" autocomplete="tel"></label></div><div class="form-grid"><label>Date<input name="date" type="date" min="${today()}" value="${esc(item.date || today())}" required></label><label>Time<select name="time" required><option ${item.time === '11:30 AM' ? 'selected' : ''}>11:30 AM</option><option ${item.time === '6:00 PM' ? 'selected' : ''}>6:00 PM</option><option ${item.time === '7:30 PM' ? 'selected' : ''}>7:30 PM</option><option ${item.time === '8:30 PM' ? 'selected' : ''}>8:30 PM</option></select></label></div><div class="form-grid"><label>Adults<input name="adults" type="number" min="0" max="20" value="${adults}" required><small class="field-help">₱599 per adult</small></label><label>Children<input name="children" type="number" min="0" max="20" value="${children}" required><small class="field-help">₱299 per child</small></label></div><div class="form-grid"><label>Table<select name="table"><option value="">Unassigned</option>${tableOptions}</select></label><label>Status<select name="status"><option ${item.status === 'Pending' || !item.status ? 'selected' : ''}>Pending</option><option ${item.status === 'Confirmed' ? 'selected' : ''}>Confirmed</option><option ${item.status === 'Seated' ? 'selected' : ''}>Seated</option><option ${item.status === 'Completed' ? 'selected' : ''}>Completed</option><option ${item.status === 'No-show' ? 'selected' : ''}>No-show</option><option ${item.status === 'Cancelled' ? 'selected' : ''}>Cancelled</option></select></label></div><label>Seating preference<input name="preference" value="${esc(item.preference || 'Any available table')}"></label><label>Special request<textarea name="request">${esc(item.request || '')}</textarea></label>`, item.id ? 'Save changes' : 'Create reservation');
  document.querySelector('#modalForm').dataset.type = 'reservation';
  document.querySelector('#modalForm').dataset.id = item.id || '';
}
function revenueAccessDenied() {
  return `${pageHeader('Restricted module', 'Access denied', 'Revenue and profitability data is limited to Administrator and Manager roles.', '')}<div class="panel empty-state"><span class="large-icon">!</span><h2>Revenue Tracking is restricted</h2><p>Your role does not have permission to view revenue, profit, or food cost information.</p></div>`;
}
function revenueForm(item = {}) {
  if (!canAccessRevenue()) return toast('Revenue Tracking is restricted to Administrator and Manager roles.', 'error');
  const defaults = { adult_customers: 0, adult_rate: 599, child_customers: 0, child_rate: 299, senior_pwd_customers: 0, senior_pwd_rate: 479 };
  const values = { ...defaults, ...item };
  const production = productionCost(values.business_date || today());
  const waste = wasteCost(values.business_date || today());
  modal(item.id ? 'Edit revenue record' : 'Record revenue', `<input type="hidden" name="id" value="${esc(item.id || '')}"><div class="form-grid"><label>Business date<input name="business_date" type="date" max="${today()}" value="${esc(values.business_date || today())}" required></label><label>Meal period<select name="meal_period"><option ${values.meal_period === 'Lunch' ? 'selected' : ''}>Lunch</option><option ${values.meal_period === 'Dinner' ? 'selected' : ''}>Dinner</option><option ${values.meal_period === 'All Day' || !values.meal_period ? 'selected' : ''}>All Day</option></select></label></div><div class="revenue-entry-grid"><label>Adult customers<input name="adult_customers" type="number" min="0" step="1" value="${values.adult_customers}" required><small class="field-help">Rate: ₱599</small></label><label>Adult rate<input name="adult_rate" type="number" min="0.01" step="0.01" value="${values.adult_rate}" required></label><label>Child customers<input name="child_customers" type="number" min="0" step="1" value="${values.child_customers}" required><small class="field-help">Rate: ₱299</small></label><label>Child rate<input name="child_rate" type="number" min="0.01" step="0.01" value="${values.child_rate}" required></label><label>Senior/PWD customers<input name="senior_pwd_customers" type="number" min="0" step="1" value="${values.senior_pwd_customers}" required><small class="field-help">Default is 20% statutory discount</small></label><label>Senior/PWD rate<input name="senior_pwd_rate" type="number" min="0.01" step="0.01" value="${values.senior_pwd_rate}" required></label></div><label>Remarks<textarea name="remarks" rows="2">${esc(values.remarks || '')}</textarea></label>${item.id ? '<label>Edit reason<input name="edit_reason" required placeholder="Why is this record changing?"></label>' : ''}<div class="revenue-preview" data-revenue-preview data-production="${production}" data-waste="${waste}"><strong>Live calculation</strong><span>Adult revenue <b data-preview="adult">₱0.00</b></span><span>Child revenue <b data-preview="child">₱0.00</b></span><span>Senior/PWD revenue <b data-preview="senior">₱0.00</b></span><span>Total customers <b data-preview="customers">0</b></span><span>Total revenue <b data-preview="total">₱0.00</b></span><span>Estimated profit <b data-preview="profit">₱${(-production - waste).toFixed(2)}</b></span></div>`, item.id ? 'Save changes' : 'Save revenue');
  document.querySelector('#modalForm').dataset.type = 'revenue';
  document.querySelector('#modalForm').dataset.id = item.id || '';
  updateRevenuePreview(document.querySelector('#modalForm'));
}
function updateRevenuePreview(form) {
  const value = name => Number(form.elements[name]?.value || 0);
  const adult = value('adult_customers') * value('adult_rate');
  const child = value('child_customers') * value('child_rate');
  const senior = value('senior_pwd_customers') * value('senior_pwd_rate');
  const total = adult + child + senior;
  const customers = value('adult_customers') + value('child_customers') + value('senior_pwd_customers');
  const profit = total - Number(form.querySelector('[data-revenue-preview]')?.dataset.production || 0) - Number(form.querySelector('[data-revenue-preview]')?.dataset.waste || 0);
  const set = (key, text) => { const target = form.querySelector(`[data-preview="${key}"]`); if (target) target.textContent = text; };
  set('adult', money(adult)); set('child', money(child)); set('senior', money(senior)); set('customers', customers); set('total', money(total)); set('profit', money(profit));
}
function revenuePage() {
  if (!canAccessRevenue()) return revenueAccessDenied();
  const cutoff = state.revenueRange === 'all' ? null : new Date(`${today()}T12:00:00`);
  if (cutoff) cutoff.setDate(cutoff.getDate() - Number(state.revenueRange));
  const rangeStart = cutoff ? `${cutoff.getFullYear()}-${String(cutoff.getMonth() + 1).padStart(2, '0')}-${String(cutoff.getDate()).padStart(2, '0')}` : '';
  const records = revenueRecords().filter(item => !rangeStart || item.business_date >= rangeStart);
  const active = records.filter(item => item.status === 'Active');
  const date = today();
  const todayRecords = active.filter(item => item.business_date === date);
  const todayTotals = todayRecords.reduce((sum, item) => sum + item.total_revenue, 0);
  const todayCustomers = todayRecords.reduce((sum, item) => sum + item.total_customers, 0);
  const todayProfit = profitability(date, { total_revenue: todayTotals }).profit;
  const rows = records.slice().sort((a, b) => String(b.business_date || '').localeCompare(String(a.business_date || ''))).slice(0, 30).map(item => {
    const result = profitability(item.business_date, item.status === 'Active' ? item : null);
    return `<tr class="${item.status === 'Voided' ? 'is-voided' : ''}"><td><strong>${esc(item.business_date)}</strong></td><td>${esc(item.meal_period)}</td><td>${item.adult_customers}</td><td>${item.child_customers}</td><td>${item.senior_pwd_customers}</td><td>${item.total_customers}</td><td class="numeric">${item.status === 'Active' ? money(item.total_revenue) : '—'}</td><td class="numeric">${money(result.production)}</td><td class="numeric">${money(result.waste)}</td><td class="numeric">${item.status === 'Active' ? money(result.profit) : '—'}</td><td><span class="status ${item.status === 'Active' ? 'status-good' : 'status-out'}">${esc(item.status)}</span></td><td><button class="ghost-btn compact-btn" data-action="edit-revenue" data-id="${item.id}" ${item.status === 'Voided' ? 'disabled' : ''}>Edit</button>${item.status === 'Active' ? `<button class="danger-btn compact-btn" data-action="void-revenue" data-id="${item.id}">Void</button>` : ''}</td></tr>`;
  }).join('') || '<tr><td colspan="12" class="empty-table">No revenue records yet. Record the first day of buffet revenue.</td></tr>';
  return `${pageHeader('Management insight', 'Revenue Tracking', 'Record buffet customers and monitor revenue, production cost, waste, and estimated profit.', '<button class="primary-btn" data-action="open-revenue">+ Record revenue</button>')}<div class="metric-grid revenue-metrics">${metric("Today's Revenue", money(todayTotals), '₱', 'green-icon', `${todayRecords.length} active entries`)}${metric('Total Customers', todayCustomers, '♙', 'purple-icon', 'Adults, children, and Senior/PWD')}${metric('Estimated Profit', money(todayProfit), '↗', 'green-icon', 'Revenue − production − waste')}${metric('Production Cost', money(productionCost(date)), '♨', 'orange-icon', 'Matched by business date')}${metric('Waste Cost', money(wasteCost(date)), '◌', 'red-icon', 'Matched by business date')}</div><div class="dashboard-grid"><div class="panel"><div class="panel-title">Profit breakdown</div><div class="panel-subtitle">${money(todayTotals)} Revenue − ${money(productionCost(date))} Production Cost − ${money(wasteCost(date))} Waste Cost = ${money(todayProfit)} Estimated Profit</div><div class="profit-breakdown"><i style="width:${todayTotals ? Math.max(4, todayTotals / Math.max(todayTotals, productionCost(date) + wasteCost(date) + 1) * 100) : 4}%"></i><i style="width:${todayTotals ? productionCost(date) / todayTotals * 100 : 0}%"></i><i style="width:${todayTotals ? wasteCost(date) / todayTotals * 100 : 0}%"></i></div><div class="legend"><span class="sales">Revenue</span><span class="cost">Production cost</span><span class="profit">Waste cost</span></div></div><div class="panel"><div class="panel-title">Default buffet rates</div><div class="analytics-stack"><div><span>Adult</span><strong>₱599.00</strong></div><div><span>Child</span><strong>₱299.00</strong></div><div><span>Senior/PWD</span><strong>₱479.00</strong></div></div><small class="panel-subtitle">Senior/PWD follows the default 20% statutory discount.</small></div></div><div class="panel revenue-records-panel"><div class="panel-header"><div><div class="panel-title">Revenue records</div><div class="panel-subtitle">Voided records remain visible for audit history.</div></div><select class="select-small" data-revenue-range><option value="30">Last 30 days</option><option value="7">Last 7 days</option><option value="all">All records</option></select></div><div class="table-scroll"><table><thead><tr><th>Date</th><th>Meal period</th><th>Adults</th><th>Children</th><th>Senior/PWD</th><th>Total customers</th><th>Revenue</th><th>Production cost</th><th>Waste cost</th><th>Estimated profit</th><th>Status</th><th>Actions</th></tr></thead><tbody>${rows}</tbody></table></div></div>`;
}
function reservationsPage() {
  const reservations = all('reservations');
  const selectedDate = state.calendarDate || today();
  const selected = new Date(`${selectedDate}T12:00:00`);
  const monthStart = new Date(selected.getFullYear(), selected.getMonth(), 1);
  const calendarStart = new Date(monthStart);
  calendarStart.setDate(1 - monthStart.getDay());
  const calendarDays = Array.from({ length: 42 }, (_, index) => {
    const date = new Date(calendarStart);
    date.setDate(calendarStart.getDate() + index);
    return date;
  });
  const dateKey = date => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  const reservationsForDate = date => reservations.filter(item => item.date === date);
  const items = reservationsForDate(selectedDate).filter(item => (state.reservationFilter === 'All' || item.status === state.reservationFilter) && (!state.query || `${item.name} ${item.email}`.toLowerCase().includes(state.query.toLowerCase())));
  const counts = status => reservationsForDate(selectedDate).filter(item => status === 'All' || item.status === status).length;
  const filters = ['All', 'Confirmed', 'Pending', 'Seated', 'Checked-in', 'Completed', 'No-show', 'Cancelled'].map(status => `<button class="${state.reservationFilter === status ? 'active' : ''}" data-reservation-filter="${status}">${status} <b>${counts(status)}</b></button>`).join('');
  const hours = ['11:30 AM', '6:00 PM', '7:30 PM', '8:30 PM'];
  const timeline = hours.map(time => {
    const matches = items.filter(item => item.time === time);
    return `<div class="reservation-time-row"><strong>${time}</strong><div class="reservation-card-list">${matches.map(item => reservationCard(item, true)).join('') || '<span class="calendar-empty">No booking</span>'}</div></div>`;
  }).join('');
  const calendarCells = calendarDays.map(date => {
    const key = dateKey(date);
    const dayReservations = reservationsForDate(key);
    const isCurrentMonth = date.getMonth() === monthStart.getMonth();
    const isSelected = key === selectedDate;
    const isToday = key === today();
    const statusDots = [...new Set(dayReservations.map(item => reservationStatusClass(item.status)))].map(status => `<i class="calendar-status-dot ${status}" aria-hidden="true"></i>`).join('');
    return `<button type="button" class="calendar-day${isCurrentMonth ? '' : ' is-outside'}${isSelected ? ' is-selected' : ''}${isToday ? ' is-today' : ''}" data-calendar-date="${key}" aria-label="${reservationDateLabel(key)}${dayReservations.length ? `, ${dayReservations.length} reservations` : ''}" aria-pressed="${isSelected}"><span>${date.getDate()}</span>${dayReservations.length ? `<div class="calendar-day-meta">${statusDots}<b>${dayReservations.length}</b></div>` : ''}</button>`;
  }).join('');
  const selectedCount = reservationsForDate(selectedDate).length;
  return `${pageHeader('Front of house', 'Reservations', 'Manage guest bookings, confirmations, arrivals, and table assignments.', '<button class="primary-btn" data-action="open-reservation">+ New reservation</button>')}<div class="reservation-workspace"><section class="panel reservation-calendar-panel"><div class="panel-header"><div><div class="panel-title">Reservation calendar</div><div class="panel-subtitle">Select a date to view its bookings</div></div><button class="text-btn" data-calendar-today>Today</button></div><div class="calendar-month-toolbar"><button type="button" class="calendar-nav" data-calendar-month="-1" aria-label="Previous month">‹</button><strong>${selected.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}</strong><button type="button" class="calendar-nav" data-calendar-month="1" aria-label="Next month">›</button></div><div class="calendar-weekdays">${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map(day => `<span>${day}</span>`).join('')}</div><div class="monthly-calendar">${calendarCells}</div><div class="calendar-legend"><span><i class="calendar-status-dot status-good"></i> Confirmed / completed</span><span><i class="calendar-status-dot status-low"></i> Pending</span><span><i class="calendar-status-dot status-out"></i> Cancelled</span></div></section><section class="panel reservation-table-panel"><div class="reservation-table-heading"><div><div class="panel-title">${reservationDateLabel(selectedDate)}</div><div class="panel-subtitle">${selectedCount} reservation${selectedCount === 1 ? '' : 's'} scheduled</div></div><span class="date-selection-badge">${selectedCount}</span></div><div class="reservation-toolbar"><div class="reservation-filters">${filters}</div><input id="tableSearch" type="search" value="${esc(state.query)}" placeholder="Search guests..." aria-label="Search guests"></div><div class="reservation-timeline">${selectedCount ? timeline : `<div class="empty-table"><strong>No reservations for ${reservationDateLabel(selectedDate)}</strong><small>Choose another date or create a new reservation.</small></div>`}</div></section></div>`;
}
function calendarPage() {
  const date = state.calendarDate || today();
  const items = all('reservations').filter(item => item.date === date).sort((a, b) => a.time.localeCompare(b.time));
  const hours = ['11:30 AM', '6:00 PM', '7:30 PM', '8:30 PM'];
  return `${pageHeader('Front of house', 'Reservation calendar', 'Review the service timeline and prepare each arrival.', '<button class="primary-btn" data-action="open-reservation">+ New reservation</button>')}<div class="calendar-controls"><button class="ghost-btn" data-calendar-step="-1">← Previous day</button><label>Service date<input id="calendarDate" type="date" value="${date}"></label><button class="ghost-btn" data-calendar-step="1">Next day →</button></div><div class="calendar-grid">${hours.map(time => { const matches = items.filter(item => item.time === time); return `<div class="calendar-slot"><strong>${time}</strong><div class="reservation-card-list">${matches.map(item => reservationCard(item)).join('') || '<span class="calendar-empty">No booking</span>'}</div></div>`; }).join('')}</div>`;
}
function deleteRecord(type, itemId) { const mapping = { ingredient: 'ingredients', recipe: 'recipes', transaction: 'inventoryTransactions', production: 'productionLogs', waste: 'wasteLogs', count: 'physicalCounts', user: 'users' }; const key = mapping[type]; if (!key) return; if (!confirm('Delete this record? This action cannot be undone.')) return; save(key, all(key).filter(x => x.id !== itemId)); toast('Record deleted'); render(); }
function handleSubmit(form) {
  const data = Object.fromEntries(new FormData(form));
  const type = form.dataset.type;
  const editId = form.dataset.id;
  const collections = {
    ingredient: 'ingredients', receiving: 'inventoryTransactions',
    waste: 'wasteLogs', production: 'productionLogs', count: 'physicalCounts'
  };
  if (type === 'revenue') {
    if (!canAccessRevenue()) return toast('Revenue Tracking is restricted.', 'error');
    const duplicate = all('revenueRecords').find(item => item.id !== editId && item.status === 'Active' && item.business_date === data.business_date && item.meal_period === data.meal_period);
    if (duplicate) return toast(`An active ${data.meal_period} record already exists for ${data.business_date}.`, 'error');
    const existing = all('revenueRecords').find(item => item.id === editId);
    const record = createRevenueRecord({
      ...data,
      id: editId || id('REV'),
      recorded_by: existing?.recorded_by || state.role,
      recorded_at: existing?.recorded_at || new Date().toISOString(),
      last_edited_by: editId ? state.role : '',
      last_edited_at: editId ? new Date().toISOString() : null,
      edit_reason: editId ? data.edit_reason : ''
    });
    save('revenueRecords', editId ? all('revenueRecords').map(item => item.id === editId ? record : item) : [record, ...all('revenueRecords')]);
  } else if (type === 'reservation') {
    const adults = data.adults === undefined ? Number(data.guests || 0) : Number(data.adults);
    const children = Number(data.children || 0);
    const record = {
      id: editId || id('RS'),
      ...data,
      adults,
      children,
      guests: adults + children,
      estimatedRevenue: adults * 599 + children * 299,
      table: data.table || ''
    };
    save('reservations', editId ? all('reservations').map(item => item.id === editId ? { ...item, ...record } : item) : [record, ...all('reservations')]);
  } else if (type === 'recipe') {
    const ingredients = state.recipeDraft.map(item => ({ ingredientId: item.ingredientId, quantity: Number(item.quantity) })).filter(item => item.ingredientId && item.quantity > 0);
    if (!ingredients.length) return toast('Add at least one inventory ingredient.', 'error');
    const record = { id: editId || id('rec'), name: data.name, category: data.category, price: Number(data.price), wastage: Number(data.wastage), ingredients };
    save('recipes', editId ? all('recipes').map(item => item.id === editId ? record : item) : [...all('recipes'), record]);
    state.recipeDraft = [];
    state.recipeForm = {};
  } else {
    const collection = collections[type];
    if (!collection) return toast('This record type cannot be saved from the browser.', 'error');
    const numeric = ['quantity', 'cost', 'stock', 'minimum', 'expected', 'actual'].reduce((result, key) => data[key] !== undefined ? { ...result, [key]: Number(data[key]) } : result, {});
    const record = { id: editId || id(type.slice(0, 4)), ...data, ...numeric };
    save(collection, editId ? all(collection).map(item => item.id === editId ? { ...item, ...record } : item) : [...all(collection), record]);
  }
  document.querySelector('#modalRoot').innerHTML = '';
  toast('Saved locally. Cloud synchronization is pending; check the sync status for completion.');
  render();
}
document.addEventListener('click', event => { if (event.target.closest('[data-action="toggle-sidebar"]')) { const control = event.target.closest('[data-action="toggle-sidebar"]'); const shell = document.querySelector('#appShell'); shell.classList.toggle('sidebar-collapsed'); const collapsed = shell.classList.contains('sidebar-collapsed'); control.textContent = collapsed ? '›' : '‹'; control.setAttribute('aria-label', collapsed ? 'Expand sidebar' : 'Collapse sidebar'); control.setAttribute('title', collapsed ? 'Expand sidebar' : 'Collapse sidebar'); return; } const groupToggle = event.target.closest('[data-action="toggle-nav-group"]'); if (groupToggle) { toggleSidebarGroup(groupToggle.dataset.group); return; } const view = event.target.closest('[data-view]')?.dataset.view; if (view) { if (!canAccess(view)) { toast('This module is not assigned to your role.', 'error'); return; } const group = sidebarGroups.find(item => item.items.some(([itemView]) => itemView === view)); if (group && !sidebarGroupState().includes(group.id)) saveSidebarGroups([...sidebarGroupState(), group.id]); state.view = view; state.query = ''; document.querySelector('#sidebar').classList.remove('open'); render(); return; } const category = event.target.closest('[data-recipe-category]')?.dataset.recipeCategory; if (category) { state.recipeCategory = category; render(); return; } const dashboardStatus = event.target.closest('[data-dashboard-status]')?.dataset.dashboardStatus; if (dashboardStatus) { state.ingredientStatus = dashboardStatus; render(); return; } const action = event.target.closest('[data-action]'); if (!action) return; const name = action.dataset.action; if (name === 'close-modal') document.querySelector('#modalRoot').innerHTML = ''; else if (name === 'open-recipe') openRecipeForm(); else if (name === 'open-revenue') revenueForm(); else if (name === 'edit-revenue') { if (!canAccessRevenue()) return toast('Revenue Tracking is restricted.', 'error'); const record = all('revenueRecords').find(x => x.id === action.dataset.id); if (record) revenueForm(record); } else if (name === 'void-revenue') { if (!canAccessRevenue()) return toast('Revenue Tracking is restricted.', 'error'); const reason = prompt('Why is this revenue record being voided?'); if (!reason?.trim()) return; save('revenueRecords', all('revenueRecords').map(x => x.id === action.dataset.id ? { ...x, status: 'Voided', voided_by: state.role, void_reason: reason.trim(), voided_at: new Date().toISOString() } : x)); toast('Revenue record voided'); render(); } else if (name === 'open-reservation') reservationForm(); else if (name === 'edit-reservation') { const record = all('reservations').find(x => x.id === action.dataset.id); if (record) reservationForm(record); } else if (name === 'toggle-recipe-picker') document.querySelector('.recipe-picker').classList.toggle('is-hidden'); else if (name === 'add-recipe-ingredient') { const form = document.querySelector('#modalForm'); const ingredientId = form.elements.draftIngredient.value; const quantity = Number(form.elements.draftQuantity.value); if (!quantity) return toast('Enter a quantity for the ingredient.', 'error'); state.recipeForm = Object.fromEntries(new FormData(form)); state.recipeDraft.push({ ingredientId, quantity }); renderRecipeModal(); } else if (name === 'remove-recipe-ingredient') { state.recipeForm = Object.fromEntries(new FormData(document.querySelector('#modalForm'))); state.recipeDraft.splice(Number(action.dataset.index), 1); renderRecipeModal(); } else if (name.startsWith('view-')) { const type = name.replace('view-', ''); const map = { ingredient: 'ingredients', recipe: 'recipes' }; const record = all(map[type]).find(x => x.id === action.dataset.id); if (record) viewRecord(type, record); } else if (name.startsWith('open-')) openForm(name.replace('open-', '')); else if (name.startsWith('edit-')) { const type = name.replace('edit-', ''); const map = { ingredient: 'ingredients', recipe: 'recipes', user: 'users' }; const record = all(map[type]).find(x => x.id === action.dataset.id); if (record) type === 'recipe' ? openRecipeForm(record) : openForm(type, record); } else if (name.startsWith('delete-')) deleteRecord(name.replace('delete-', ''), action.dataset.id); });
document.addEventListener('submit', async event => {
  if (event.target.id === 'loginForm') {
    event.preventDefault();
    const form = event.target;
    const submit = form.querySelector('button[type="submit"]');
    submit.disabled = true;
    try {
      const { data, error } = await window.supabaseClient.auth.signInWithPassword({
        email: form.elements.email.value.trim(),
        password: form.elements.password.value
      });
      if (error) throw error;
      await openAuthenticatedSession(data.session);
    } catch (error) {
      console.error('Authentication failed.', error);
      login('Sign-in failed. Check your credentials and network connection.');
    } finally {
      submit.disabled = false;
    }
  }
  if (event.target.id === 'passwordRecoveryForm') {
    event.preventDefault();
    try {
      const { error } = await window.supabaseClient.auth.updateUser({ password: event.target.elements.password.value });
      if (error) throw error;
      passwordRecoveryMode = false;
      window.location.hash = '';
      toast('Password updated. You are signed in.');
      const { data, error: sessionError } = await window.supabaseClient.auth.getSession();
      if (sessionError) throw sessionError;
      await openAuthenticatedSession(data.session);
    } catch (error) {
      console.error('Password update failed.', error);
      login(error.message || 'Password update failed. Request a new reset link.');
    }
  }
  if (event.target.id === 'modalForm') { event.preventDefault(); handleSubmit(event.target); }
});
document.addEventListener('input', event => { if (event.target.id === 'tableSearch') { state.query = event.target.value; render(); const search = document.querySelector('#tableSearch'); search.focus(); search.setSelectionRange(state.query.length, state.query.length); } });
document.addEventListener('change', event => { const filter = event.target.dataset.filter; if (!filter) return; state[filter] = event.target.value.startsWith('All ') ? 'All' : event.target.value; render(); });
document.querySelector('#mobileMenu').addEventListener('click', () => document.querySelector('#sidebar').classList.toggle('open'));
document.addEventListener('change', event => {
  if (event.target.matches('[data-revenue-range]')) {
    state.revenueRange = event.target.value;
    render();
  }
});
function pendingSyncKey() { return `costtrack_pending_sync_${state.user?.id || 'anonymous'}`; }
function readPendingWrites() {
  const persisted = JSON.parse(localStorage.getItem(pendingSyncKey()) || '{}');
  return { ...persisted, ...(volatilePending[state.user?.id] || {}) };
}
function writePendingWrites(pending) {
  const sensitive = {};
  const persisted = {};
  Object.entries(pending).forEach(([key, value]) => (volatileCollections.has(value.collection) ? sensitive : persisted)[key] = value);
  volatilePending[state.user.id] = sensitive;
  localStorage.setItem(pendingSyncKey(), JSON.stringify(persisted));
}
function queuePendingWrites(collection, writes) {
  const pending = readPendingWrites();
  for (const write of writes) {
    const recordId = write.type === 'remove' ? write.id : String(write.record.id);
    const pendingId = `${collection}:${recordId}`;
    const priorOperation = pending[pendingId];
    if (write.type === 'remove' && priorOperation?.type === 'upsert' && !priorOperation.expectedVersion) {
      delete pending[pendingId];
      continue;
    }
    pending[pendingId] = {
      collection, ...write, recordId,
      expectedVersion: priorOperation?.expectedVersion ?? window.supabaseRecord.version(collection, recordId) ?? null,
      opId: id('sync')
    };
  }
  writePendingWrites(pending);
}
let processingPendingSync = false;
async function processPendingSync() {
  if (!supabaseSyncEnabled || processingPendingSync || !state.user || !navigator.onLine) return;
  processingPendingSync = true;
  let syncedChanges = false;
  let refreshIngredients = false;
  let activePendingId = null;
  setSyncStatus('syncing');
  try {
    while (true) {
      const pending = readPendingWrites();
      const entry = Object.entries(pending)[0];
      if (!entry) break;
      const [pendingId, operation] = entry;
      activePendingId = pendingId;
      if (operation.type === 'remove') await window.supabaseRecord.remove(operation.collection, operation.recordId, operation.expectedVersion);
      else await window.supabaseRecord.upsert(operation.collection, operation.record, operation.expectedVersion);
      if (operation.type === 'remove') {
        const remaining = all(operation.collection).filter(record => String(record.id) !== operation.recordId);
        if (volatileCollections.has(operation.collection)) volatileRecords[operation.collection] = remaining;
        else localStorage.setItem(`costtrack_${operation.collection}`, JSON.stringify(remaining));
      } else {
        const records = all(operation.collection);
        const index = records.findIndex(record => String(record.id) === operation.recordId);
        if (index < 0) records.push(operation.record);
        else records[index] = operation.record;
        if (volatileCollections.has(operation.collection)) volatileRecords[operation.collection] = records;
        else localStorage.setItem(`costtrack_${operation.collection}`, JSON.stringify(records));
      }
      const latest = readPendingWrites();
      if (latest[pendingId]?.opId === operation.opId) {
        delete latest[pendingId];
        writePendingWrites(latest);
      }
      syncedChanges = true;
      refreshIngredients = refreshIngredients || ['inventoryTransactions', 'productionLogs', 'wasteLogs', 'physicalCounts'].includes(operation.collection);
      activePendingId = null;
    }
    if (refreshIngredients) {
      const currentIngredients = await window.supabaseRecord.load('ingredients');
      localStorage.setItem('costtrack_ingredients', JSON.stringify(currentIngredients));
    }
    failedPendingId = null;
    setSyncStatus('connected');
    if (syncedChanges) {
      render();
      toast('Changes saved to cloud.');
    }
  } catch (error) {
    console.error('Cloud synchronization failed.', error);
    failedPendingId = activePendingId;
    setSyncStatus('error', error.message);
    toast(activePendingId
      ? 'Cloud synchronization failed. Your saved changes remain queued; select the sync status to retry.'
      : 'Cloud changes saved, but updated stock could not be reloaded. Select the sync status to retry.', 'error');
  } finally {
    processingPendingSync = false;
  }
}
async function syncWithSupabase() {
  const collectionsByRole = {
    Administrator: KEYS,
    Manager: KEYS.filter(key => key !== 'users'),
    'Inventory Clerk': ['ingredients', 'inventoryTransactions', 'physicalCounts'],
    'Chef / Kitchen Staff': ['ingredients', 'recipes', 'productionLogs', 'wasteLogs'],
    Receptionist: ['ingredients', 'recipes', 'productionLogs', 'wasteLogs', 'physicalCounts', 'reservations', 'restaurantTables']
  };
  const collections = collectionsByRole[state.role] || [];
  setSyncStatus('syncing');
  volatileRecords.revenueRecords = [];
  volatileRecords.users = [];
  localStorage.removeItem('costtrack_revenueRecords');
  localStorage.removeItem('costtrack_users');
  KEYS.filter(key => !collections.includes(key) && !volatileCollections.has(key))
    .forEach(key => localStorage.removeItem(`costtrack_${key}`));
  for (const key of collections) {
    const remoteRecords = await window.supabaseRecord.load(key);
    if (volatileCollections.has(key)) volatileRecords[key] = remoteRecords;
    else localStorage.setItem(`costtrack_${key}`, JSON.stringify(remoteRecords));
  }
  if (!canAccessRevenue()) volatileRecords.revenueRecords = [];
  supabaseSyncEnabled = true;
  await processPendingSync();
  render();
}
async function openAuthenticatedSession(session) {
  if (!session?.user) throw new Error('No authenticated Supabase session was returned.');
  const { data: profile, error } = await window.supabaseClient
    .from('profiles')
    .select('id,email,full_name,role')
    .eq('id', session.user.id)
    .single();
  if (error || !profile || !roleAccess[profile.role]) {
    await window.supabaseClient.auth.signOut();
    throw new Error('Your account has no valid CostTrack role profile. Ask an administrator to provision your profile.');
  }
  state.user = profile;
  state.role = profile.role;
  window.supabaseRecord.clearVersions();
  state.view = window.location.hash.slice(1) || 'dashboard';
  document.querySelector('#loginScreen').classList.add('is-hidden');
  document.querySelector('#appShell').classList.remove('is-hidden');
  document.querySelector('#loadingState').classList.remove('is-hidden');
  try {
    await syncWithSupabase();
    document.querySelector('#loadingState').classList.add('is-hidden');
  } catch (syncError) {
    console.error('Initial cloud load failed.', syncError);
    setSyncStatus('error', syncError.message);
    document.querySelector('#loadingState').classList.add('is-hidden');
    toast('Cloud data could not be loaded. Check access or connection, then retry.', 'error');
  }
  render();
}
document.querySelector('#signOutButton').addEventListener('click', async () => {
  await processPendingSync();
  if (Object.keys(readPendingWrites()).length && !confirm('Some changes have not reached the cloud. Sign out and discard this device’s queued changes?')) return;
  const signedOutUserId = state.user.id;
  const { error } = await window.supabaseClient.auth.signOut();
  if (error) {
    toast('Sign out failed. Please try again.', 'error');
    console.error('Sign out failed.', error);
    return;
  }
  state.user = null;
  state.role = null;
  supabaseSyncEnabled = false;
  KEYS.forEach(key => localStorage.removeItem(`costtrack_${key}`));
  localStorage.removeItem(`costtrack_pending_sync_${signedOutUserId}`);
  delete volatilePending[signedOutUserId];
  volatileRecords.revenueRecords = [];
  volatileRecords.users = [];
  document.querySelector('#appShell').classList.add('is-hidden');
  document.querySelector('#loginScreen').classList.remove('is-hidden');
  login();
});
async function retryCloudSync() {
  if (!state.user) return;
  try {
    await syncWithSupabase();
  } catch (error) {
    console.error('Cloud sync retry failed.', error);
    setSyncStatus('error', error.message);
    toast('Cloud sync retry failed. Your local data remains queued.', 'error');
  }
}
document.querySelector('#syncStatus').addEventListener('click', () => {
  if (document.querySelector('#syncStatus').dataset.state === 'error') retryCloudSync();
});
document.querySelector('#discardSyncButton').addEventListener('click', async () => {
  if (!failedPendingId) return;
  const pending = readPendingWrites();
  const operation = pending[failedPendingId];
  if (!operation) {
    failedPendingId = null;
    return retryCloudSync();
  }
  const subject = operation.type === 'remove' ? operation.recordId : operation.record.name || operation.record.id;
  if (!confirm(`Discard the failed change for ${subject} and reload the cloud copy?`)) return;
  delete pending[failedPendingId];
  writePendingWrites(pending);
  failedPendingId = null;
  toast('Failed change discarded. Reloading cloud data.', 'error');
  await retryCloudSync();
});
document.querySelector('#loginScreen').addEventListener('click', async event => {
  if (event.target.id !== 'resetPasswordButton') return;
  const email = document.querySelector('#loginForm [name="email"]').value.trim();
  if (!email) return login('Enter your work email first, then request a reset link.');
  const { error } = await window.supabaseClient.auth.resetPasswordForEmail(email, { redirectTo: `${window.location.origin}${window.location.pathname}#recovery` });
  if (error) {
    console.error('Password reset request failed.', error);
    return login('Could not send the reset email. Check the address and try again.');
  }
  login('If an account exists for this address, a password reset email has been sent.');
});
window.addEventListener('online', retryCloudSync);
window.addEventListener('offline', () => setSyncStatus('offline'));
window.supabaseClient.auth.onAuthStateChange((event, session) => {
  if (event === 'PASSWORD_RECOVERY') {
    passwordRecoveryMode = true;
    login();
    return;
  }
  if (event === 'SIGNED_OUT' && state.user) {
    delete volatilePending[state.user.id];
    volatileRecords.revenueRecords = [];
    volatileRecords.users = [];
    state.user = null;
    state.role = null;
    supabaseSyncEnabled = false;
    KEYS.forEach(key => localStorage.removeItem(`costtrack_${key}`));
    document.querySelector('#appShell').classList.add('is-hidden');
    document.querySelector('#loginScreen').classList.remove('is-hidden');
    login('Your session ended. Sign in again to continue.');
  }
  if (event === 'TOKEN_REFRESHED' && !session) setSyncStatus('error', 'Your session expired. Sign in again.');
});
document.querySelector('#loadingState').classList.remove('is-hidden');
window.supabaseClient.auth.getSession().then(({ data, error }) => {
  if (error) throw error;
  if (data.session) return openAuthenticatedSession(data.session);
  document.querySelector('#loadingState').classList.add('is-hidden');
  login();
  setSyncStatus(navigator.onLine ? 'offline' : 'offline');
}).catch(error => {
  console.error('Could not restore the Supabase session.', error);
  document.querySelector('#loadingState').classList.add('is-hidden');
  setSyncStatus('offline', error.message);
  login('Secure sign-in is currently unavailable. Check your connection and try again.');
});

/* Accessible UI refinements kept in this layer so the existing local data model remains unchanged. */
function modal(title, content, submit = 'Save record') {
  modalOpener = document.activeElement;
  const submitButton = submit ? `<button class="primary-btn modal-submit" type="submit">${submit}</button>` : '';
  document.querySelector('#modalRoot').innerHTML = `<div class="modal-backdrop" role="presentation"><div class="modal" role="dialog" aria-modal="true" aria-labelledby="modalTitle" tabindex="-1"><div class="modal-header"><div><div class="eyebrow">CostTrack workspace</div><h2 id="modalTitle">${title}</h2></div></div><form id="modalForm" novalidate>${content}<div class="modal-actions"><button type="button" class="ghost-btn" data-action="close-modal">Cancel</button>${submitButton}</div></form></div></div>`;
  const form = document.querySelector('#modalForm');
  form.querySelectorAll('label').forEach((label, index) => {
    const control = label.querySelector('input, select, textarea');
    if (!control) return;
    if (!control.id) control.id = `modal-${control.name || 'field'}-${index}`;
    label.htmlFor = control.id;
    if (control.required) label.classList.add('required-field');
    const unit = { cost: '₱', unitCost: '₱', price: '₱', quantity: 'qty', stock: 'qty', minimum: 'qty', expected: 'qty', actual: 'qty', wastage: '%' }[control.name];
    if (unit) { label.dataset.unit = unit; control.classList.add('has-unit'); }
  });
  const first = form.querySelector('input:not([type="hidden"]), select, textarea, button');
  requestAnimationFrame(() => first?.focus());
}

function restoreModalFocus() {
  if (!modalOpener) return;
  const action = modalOpener.dataset?.action;
  const recordId = modalOpener.dataset?.id;
  const replacement = [...document.querySelectorAll('[data-action]')].find(element =>
    element.dataset.action === action && element.dataset.id === recordId
  );
  const focusTarget = replacement || (modalOpener.isConnected ? modalOpener : null);
  requestAnimationFrame(() => focusTarget?.focus());
  modalOpener = null;
}

function closeModal() {
  document.querySelector('#modalRoot').innerHTML = '';
  restoreModalFocus();
}
new MutationObserver(() => {
  if (!document.querySelector('#modalRoot').firstElementChild && modalOpener) restoreModalFocus();
}).observe(document.querySelector('#modalRoot'), { childList: true });

function showFieldError(control, message) {
  const label = control.closest('label');
  label?.classList.add('has-error');
  let error = label?.querySelector('.field-error');
  if (!error) {
    error = document.createElement('span');
    error.className = 'field-error';
    label?.append(error);
  }
  error.textContent = message;
  control.setAttribute('aria-invalid', 'true');
}

function clearFieldErrors(form) {
  form.querySelectorAll('.has-error').forEach(label => label.classList.remove('has-error'));
  form.querySelectorAll('.field-error').forEach(error => error.remove());
  form.querySelectorAll('[aria-invalid="true"]').forEach(control => control.removeAttribute('aria-invalid'));
}

function normaliseRenderedStatuses() {
  document.querySelectorAll('.status, .stock-state').forEach(element => {
    const value = element.textContent.trim().toLowerCase();
    const kind = value.includes('cancel') ? 'out' : value.includes('pending') ? 'low' : value.includes('out') ? 'out' : value.includes('low') || value.includes('short') ? 'low' : value.includes('over') ? 'over' : 'healthy';
    element.classList.remove('status-good', 'status-low', 'status-out', 'status-over', 'healthy', 'low', 'out', 'over');
    element.classList.add(`status-${kind}`);
    element.insertAdjacentHTML('afterbegin', `<span class="status-dot" aria-hidden="true"></span>`);
  });
}

function render() {
  if (!state.user || !state.role) return;
  if (state.view === 'revenue' && !canAccessRevenue()) {
    document.querySelector('#sidebar').innerHTML = nav();
    document.querySelector('#pageCrumb').textContent = 'Access denied';
    app.innerHTML = revenueAccessDenied();
    return;
  }
  if (!canAccess(state.view)) state.view = roleAccess[state.role][0];
  document.querySelector('#sidebar').innerHTML = nav();
  document.querySelector('#pageCrumb').textContent = ({ dashboard: 'Dashboard', ingredients: 'Ingredients', receiving: 'Inventory receiving', recipes: 'Recipes', production: 'Production logs', waste: 'Waste logs', counts: 'Physical count', reports: 'Reports & analytics', revenue: 'Revenue Tracking', users: 'User management', roles: 'Role management', settings: 'System settings', reservations: 'Reservations', calendar: 'Reservation calendar' })[state.view];
  const pages = { dashboard: roleDashboard, ingredients: ingredientCardsPage, receiving: receivingPage, recipes: recipeCardsPage, production: () => logsPage('production'), waste: () => logsPage('waste'), counts: countsPage, reports: reportsPage, revenue: revenuePage, users: usersPage, roles: usersPage, settings: usersPage, reservations: reservationsPage, calendar: calendarPage };
  app.innerHTML = pages[state.view]();
  const identity = document.querySelector('#currentUser');
  if (identity) identity.textContent = `${state.user.full_name || state.user.email} · ${state.role}`;
  const period = document.querySelector('#reportingPeriod');
  if (period) period.textContent = `◷ ${new Date().toLocaleDateString('en-US', { month: 'long', year: 'numeric' })} reporting period`;
  const revenueRange = document.querySelector('[data-revenue-range]');
  if (revenueRange) revenueRange.value = state.revenueRange;
  normaliseRenderedStatuses();
  if (state.view === 'ingredients') {
    const toolbar = document.querySelector('.catalog-toolbar');
    if (toolbar && !toolbar.querySelector('[data-action="clear-filters"]')) toolbar.insertAdjacentHTML('beforeend', '<button class="ghost-btn clear-filters" data-action="clear-filters">Clear filters</button>');
  }
}

function actions(type, itemId) {
  const labels = { view: 'View', edit: 'Edit', delete: 'Delete' };
  const icon = name => name === 'view' ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6Z"/><circle cx="12" cy="12" r="2.5"/></svg>' : name === 'edit' ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4 16.5-.8 4.3 4.3-.8L19 8.5 15.5 5 4 16.5Z"/><path d="m14 6.5 3.5 3.5"/></svg>' : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3m-9 0 1 13h10l1-13M10 11v5m4-5v5"/></svg>';
  const editable = ['ingredient', 'recipe', 'user'].includes(type);
  const deletable = ['ingredient', 'recipe'].includes(type);
  return `<div class="row-actions">${editable ? `<button type="button" data-action="view-${type}" data-id="${itemId}" aria-label="${labels.view}"><span class="tooltip">${labels.view}</span>${icon('view')}</button><button type="button" data-action="edit-${type}" data-id="${itemId}" aria-label="${labels.edit}"><span class="tooltip">${labels.edit}</span>${icon('edit')}</button>` : ''}${deletable ? `<button type="button" class="danger-action" data-action="delete-${type}" data-id="${itemId}" aria-label="${labels.delete}"><span class="tooltip">${labels.delete}</span>${icon('delete')}</button>` : ''}</div>`;
}

function deleteRecord(type, itemId) {
  const mapping = { ingredient: 'ingredients', recipe: 'recipes', transaction: 'inventoryTransactions', production: 'productionLogs', waste: 'wasteLogs', count: 'physicalCounts', user: 'users' };
  const key = mapping[type]; if (!key) return;
  const record = all(key).find(item => item.id === itemId);
  if (type === 'ingredient' && (all('recipes').some(item => item.ingredients.some(line => line.ingredientId === itemId)) || all('inventoryTransactions').some(item => item.ingredientId === itemId) || all('wasteLogs').some(item => item.ingredientId === itemId) || all('physicalCounts').some(item => item.ingredientId === itemId))) {
    return toast('This ingredient is referenced by recipe or inventory history and cannot be deleted.', 'error');
  }
  if (type === 'recipe' && all('productionLogs').some(item => item.recipeId === itemId)) {
    return toast('This recipe is referenced by production history and cannot be deleted.', 'error');
  }
  const name = record?.name || ingredient(record?.ingredientId)?.name || recipe(record?.recipeId)?.name || 'this record';
  if (!confirm(`Delete ${name}? This can't be undone.`)) return;
  save(key, all(key).filter(item => item.id !== itemId));
  toast(`${name} deleted`);
  render();
}

function exportRecipeReport(format) {
  const rows = [
    ['Recipe', 'Cost', 'Price', 'Food cost %', 'Margin'],
    ...all('recipes').map(item => {
      const cost = computedRecipeCost(item);
      return [item.name, cost, Number(item.price), `${(cost / item.price * 100).toFixed(1)}%`, item.price - cost];
    })
  ];
  if (format === 'Excel') {
    if (!window.XLSX) throw new Error('Excel export is unavailable. Check your connection and try again.');
    const workbook = window.XLSX.utils.book_new();
    window.XLSX.utils.book_append_sheet(workbook, window.XLSX.utils.aoa_to_sheet(rows), 'Recipe Costs');
    window.XLSX.writeFile(workbook, 'costtrack-recipe-report.xlsx');
    return;
  }
  const output = rows.map(row => row.map(value => `"${String(value).replace(/"/g, '""')}"`).join(',')).join('\r\n');
  const blob = new Blob([output], { type: 'text/csv;charset=utf-8' });
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  link.href = url;
  link.download = 'costtrack-recipe-report.csv';
  link.click();
  URL.revokeObjectURL(url);
}

function reportsPage() {
  const ingredients = all('ingredients');
  const counts = all('physicalCounts');
  const shortages = counts.filter(item => item.actual < item.expected);
  const recipes = all('recipes');
  const exportMenu = `<div class="export-menu"><button class="secondary-btn" data-action="toggle-export">Export report <span aria-hidden="true">⌄</span></button><div class="export-options is-hidden" role="menu"><button data-export="PDF" role="menuitem">PDF</button><button data-export="CSV" role="menuitem">CSV</button><button data-export="Excel" role="menuitem">Excel</button></div></div>`;
  const recipeRows = recipes.map(item => { const cost = computedRecipeCost(item); return `<tr><td><strong>${esc(item.name)}</strong></td><td>${money(cost)}</td><td>${money(item.price)}</td><td>${(cost / item.price * 100).toFixed(1)}%</td><td class="positive">${money(item.price - cost)}</td></tr>`; }).join('');
  return `${pageHeader('Management insight', 'Reports & analytics', 'Turn operational data into decisions for your next kitchen shift.', exportMenu)}<div class="report-grid"><div class="panel report-card"><div class="panel-title">Inventory valuation</div><div class="report-big">${money(inventoryValue())}</div><p>Current value across ${ingredients.length} tracked ingredients</p><div class="valuation-list">${ingredients.map(item => `<div><span>${esc(item.name)}</span><strong>${money(item.stock * item.cost)}</strong></div>`).join('')}</div></div><div class="panel report-card"><div class="panel-title">Waste performance</div><div class="report-big">${money(wasteCost())}</div><p>Total recorded waste cost this month</p><div class="progress-line"><i style="width:${Math.min(100, wasteCost() / 20)}%"></i></div><small class="up">12.4% lower than previous month</small></div><div class="panel report-card"><div class="panel-title">Variance snapshot</div><div class="report-big">${shortages.length}<span class="muted-big"> shortages</span></div><p>Across ${counts.length} completed counts</p><div class="variance-list">${counts.map(item => { const variance = item.actual - item.expected; const over = variance > 0; return `<span>${esc(ingredient(item.ingredientId)?.name || 'Unknown')} <b class="${over ? 'positive' : 'negative'}">${over ? '+' : '−'}${Math.abs(variance).toFixed(2)} ${esc(ingredient(item.ingredientId)?.unit || '')}</b></span>`; }).join('')}</div></div></div><div class="report-tables"><div class="panel"><div class="panel-header"><div><div class="panel-title">Recipe cost report</div><div class="panel-subtitle">Cost per serving and profitability overview</div></div></div>${recipes.length ? `<div class="table-scroll report-table-scroll"><table><thead><tr><th>Recipe</th><th>Cost</th><th>Price</th><th>Food cost %</th><th>Margin</th></tr></thead><tbody>${recipeRows}</tbody></table></div>` : '<div class="empty-report"><span aria-hidden="true">◇</span><strong>No recipe cost data yet</strong><p>Create a recipe to start tracking serving cost and margin.</p><button class="primary-btn" data-action="open-recipe">Create recipe</button></div>'}</div></div>`;
}

document.addEventListener('keydown', event => {
  const dialog = document.querySelector('.modal[role="dialog"]');
  if (!dialog) return;
  if (event.key === 'Escape') { event.preventDefault(); document.querySelector('#modalRoot').innerHTML = ''; return; }
  if (event.key !== 'Tab') return;
  const focusable = [...dialog.querySelectorAll('button, input, select, textarea, [tabindex]:not([tabindex="-1"])')].filter(item => !item.disabled);
  if (!focusable.length) return;
  const first = focusable[0]; const last = focusable[focusable.length - 1];
  if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
});
document.addEventListener('click', event => {
  const confirmButton = event.target.closest('[data-action="confirm-reservation"]');
  if (confirmButton) {
    if (!canAccess('reservations')) return toast('Your role cannot confirm reservations.', 'error');
    const reservation = all('reservations').find(item => item.id === confirmButton.dataset.id);
    if (!reservation || reservation.status !== 'Pending') {
      toast('This reservation is no longer pending.', 'error');
      render();
      return;
    }
    save('reservations', all('reservations').map(item =>
      item.id === reservation.id ? { ...item, status: 'Confirmed' } : item
    ));
    toast(`Reservation for ${reservation.name} confirmed.`);
    render();
    return;
  }
  const calendarDate = event.target.closest('[data-calendar-date]');
  if (calendarDate) { state.calendarDate = calendarDate.dataset.calendarDate; state.query = ''; render(); return; }
  const calendarMonth = event.target.closest('[data-calendar-month]');
  if (calendarMonth) {
    const date = new Date(`${state.calendarDate || today()}T12:00:00`);
    date.setDate(1);
    date.setMonth(date.getMonth() + Number(calendarMonth.dataset.calendarMonth));
    state.calendarDate = date.toISOString().slice(0, 10);
    state.query = '';
    render();
    return;
  }
  if (event.target.closest('[data-calendar-today]')) { state.calendarDate = today(); state.query = ''; render(); return; }
  const filter = event.target.closest('[data-reservation-filter]');
  if (filter) { state.reservationFilter = filter.dataset.reservationFilter; state.query = ''; render(); return; }
  const step = event.target.closest('[data-calendar-step]');
  if (step) { const date = new Date(`${state.calendarDate || today()}T12:00:00`); date.setDate(date.getDate() + Number(step.dataset.calendarStep)); state.calendarDate = date.toISOString().slice(0, 10); render(); return; }
});
document.addEventListener('change', event => {
  if (event.target.id === 'calendarDate') { state.calendarDate = event.target.value; render(); }
  if (event.target.id === 'tableSearch') { state.query = event.target.value; render(); }
});
document.addEventListener('input', event => {
  if (event.target.closest('#modalForm[data-type="revenue"]')) updateRevenuePreview(event.target.closest('#modalForm'));
  if (event.target.id === 'tableSearch') { state.query = event.target.value; render(); document.querySelector('#tableSearch')?.focus(); }
});
window.addEventListener('hashchange', () => {
  const view = window.location.hash.slice(1);
  if (!view) return;
  state.view = view;
  render();
});

document.addEventListener('click', event => {
  const backdrop = event.target.classList.contains('modal-backdrop');
  if (backdrop) document.querySelector('#modalRoot').innerHTML = '';
  const clear = event.target.closest('[data-action="clear-filters"]');
  if (clear) { state.query = ''; state.ingredientStatus = 'All'; state.ingredientCategory = 'All'; state.ingredientUnit = 'All'; render(); }
  const exportToggle = event.target.closest('[data-action="toggle-export"]');
  if (exportToggle) document.querySelector('.export-options')?.classList.toggle('is-hidden');
  const exportButton = event.target.closest('[data-export]');
  if (exportButton) {
    const format = exportButton.dataset.export;
    document.querySelector('.export-options')?.classList.add('is-hidden');
    if (format === 'PDF') { window.print(); toast('Print dialog opened for PDF export'); }
    else {
      try {
        exportRecipeReport(format);
        toast(`${format} export downloaded`);
      } catch (error) {
        console.error('Report export failed.', error);
        toast(error.message || 'Report export failed.', 'error');
      }
    }
  }
  const mobileMenu = event.target.closest('#mobileMenu');
  if (mobileMenu) mobileMenu.setAttribute('aria-expanded', String(document.querySelector('#sidebar').classList.contains('open')));
});

document.addEventListener('submit', event => {
  if (event.target.id !== 'modalForm') return;
  event.preventDefault();
  const form = event.target; clearFieldErrors(form);
  let valid = true;
  form.querySelectorAll('[required]').forEach(control => {
    if (!String(control.value).trim()) { showFieldError(control, 'This field is required.'); valid = false; }
  });
  form.querySelectorAll('input[type="number"]').forEach(control => {
    if (control.value !== '' && (!Number.isFinite(Number(control.value)) || Number(control.value) < Number(control.min || 0))) { showFieldError(control, `Enter a number of ${control.min && Number(control.min) > 0 ? 'at least ' + control.min : 'zero or more'}.`); valid = false; }
    if (form.dataset.type === 'revenue' && ['adult_customers', 'child_customers', 'senior_pwd_customers'].includes(control.name) && !Number.isInteger(Number(control.value))) { showFieldError(control, 'Enter a whole number of customers.'); valid = false; }
  });
  if (form.dataset.type === 'revenue' && ['adult_customers', 'child_customers', 'senior_pwd_customers'].reduce((sum, name) => sum + Number(form.elements[name]?.value || 0), 0) < 1) { showFieldError(form.elements.adult_customers, 'At least one customer is required.'); valid = false; }
  if (!valid) { event.stopImmediatePropagation(); form.querySelector('.has-error input, .has-error select, .has-error textarea')?.focus(); return; }
  event.stopImmediatePropagation();
  const submit = form.querySelector('.modal-submit'); submit.disabled = true; submit.classList.add('is-loading'); submit.setAttribute('aria-busy', 'true'); submit.textContent = 'Saving…';
  handleSubmit(form);
}, true);
