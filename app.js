const data = {
  dishes: [
    { name: 'Chicken Adobo', emoji: '🍗', category: 'Main course', price: 185, cost: 64.5, sold: 248, status: 'Available' },
    { name: 'Beef Burger', emoji: '🍔', category: 'Main course', price: 220, cost: 91.2, sold: 184, status: 'Available' },
    { name: 'Carbonara', emoji: '🍝', category: 'Pasta', price: 195, cost: 72.8, sold: 172, status: 'Available' },
    { name: 'Halo-Halo', emoji: '🍧', category: 'Dessert', price: 145, cost: 38.4, sold: 126, status: 'Available' },
    { name: 'Pork Sisig', emoji: '🥘', category: 'Main course', price: 210, cost: 78.6, sold: 111, status: 'Low stock' }
  ],
  ingredients: [
    { name: 'Chicken', unit: 'kg', stock: '3.2 kg', cost: 185, reorder: '5 kg', percent: 32, status: 'Low stock', tone: 'low', emoji: '🍗' },
    { name: 'Rice', unit: 'kg', stock: '18 kg', cost: 58, reorder: '10 kg', percent: 82, status: 'Healthy', tone: 'good', emoji: '🌾' },
    { name: 'Garlic', unit: 'kg', stock: '1.1 kg', cost: 220, reorder: '2 kg', percent: 42, status: 'Reorder soon', tone: 'warn', emoji: '🧄' },
    { name: 'Onion', unit: 'kg', stock: '4.8 kg', cost: 120, reorder: '3 kg', percent: 70, status: 'Healthy', tone: 'good', emoji: '🧅' },
    { name: 'Cooking Oil', unit: 'L', stock: '2.4 L', cost: 96, reorder: '5 L', percent: 28, status: 'Low stock', tone: 'low', emoji: '🫗' },
    { name: 'Beef', unit: 'kg', stock: '5.5 kg', cost: 420, reorder: '4 kg', percent: 75, status: 'Healthy', tone: 'good', emoji: '🥩' },
    { name: 'Pasta', unit: 'kg', stock: '6 kg', cost: 115, reorder: '4 kg', percent: 66, status: 'Healthy', tone: 'good', emoji: '🍝' }
  ]
};

const money = value => `₱${value.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const icons = ['◒', '◉', '◌', '✦'];
const app = document.querySelector('#app');
const pageCrumb = document.querySelector('#pageCrumb');
let role = 'Admin';
const workflow = {
  nextOrder: 1002,
  orders: [
    { id: 1001, table: 5, items: [['Burger', 2], ['Fries', 1], ['Coke', 2]], status: 'Ready', total: 580, payment: 'Pending' },
    { id: 1000, table: 2, items: [['Chicken Meal', 2], ['Soft Drinks', 2]], status: 'Preparing', total: 520, payment: 'Pending' },
    { id: 999, table: 8, items: [['Spaghetti', 1], ['Halo-Halo', 1]], status: 'Pending', total: 310, payment: 'Pending' }
  ],
  cart: [{ name: 'Burger', price: 220, qty: 2 }, { name: 'Fries', price: 70, qty: 1 }, { name: 'Coke', price: 35, qty: 2 }],
  selectedPayment: 'Cash'
};
const posProducts = [
  ['Burger', '🍔', 220, 'Main Course'], ['Chicken Meal', '🍗', 260, 'Main Course'],
  ['Spaghetti', '🍝', 195, 'Main Course'], ['Fries', '🍟', 70, 'Snacks'],
  ['Soft Drinks', '🥤', 35, 'Drinks'], ['Halo-Halo', '🍧', 145, 'Desserts']
];

function svgChart() {
  const points = [52, 43, 48, 35, 40, 29, 33, 25, 31, 20, 24, 17];
  const x = i => 35 + i * 45;
  const y = value => 172 - value * 1.35;
  const line = points.map((p, i) => `${x(i)},${y(p)}`).join(' ');
  const area = `35,172 ${line} 530,172`;
  return `<svg class="chart-svg" viewBox="0 0 565 205" preserveAspectRatio="none">
    <defs><linearGradient id="salesFill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#8bd2c2" stop-opacity=".35"/><stop offset="1" stop-color="#8bd2c2" stop-opacity="0"/></linearGradient></defs>
    ${[35,75,115,155].map(v => `<line class="chart-grid-line" x1="35" y1="${v}" x2="530" y2="${v}"/>`).join('')}
    <polygon class="sales-area" points="${area}"/><polyline class="sales-line" points="${line}"/>
    ${points.map((p,i) => `<circle class="sales-dot" cx="${x(i)}" cy="${y(p)}" r="3"/>`).join('')}
    ${['May 01','May 05','May 10','May 15','May 20','May 25','May 30'].map((m,i) => `<text class="chart-label" x="${35 + i*82}" y="198">${m}</text>`).join('')}
  </svg>`;
}

function header(title, text, action = '＋ Add new') {
  return `<div class="section-heading"><div class="eyebrow">CostTrack workspace</div><div class="welcome-row"><div><h1>${title}</h1><p>${text}</p></div><button class="primary-btn">${action}</button></div></div>`;
}

function dashboard() {
  const isKitchen = role === 'Kitchen Staff';
  const isCashier = role === 'Cashier';
  const isManager = role === 'Manager';
  const dashboardTitle = isKitchen ? 'Kitchen, in control.' : isCashier ? 'Service starts here.' : isManager ? 'Good morning, manager.' : role === 'Inventory Staff' ? 'Stock, in control.' : 'Good morning, Jamie.';
  const dashboardText = isKitchen ? 'Keep recipes consistent and food costs on target today.' : isCashier ? 'Create orders, follow kitchen progress, and close every sale.' : isManager ? 'Your restaurant performance, at a glance.' : role === 'Inventory Staff' ? 'Monitor stock health and keep every station supplied.' : 'Here is what is happening across Basil & Ash today.';
  return `${header(dashboardTitle, dashboardText, isCashier ? '＋ Create order' : '＋ Add menu item')}
    <div class="role-context"><span class="pill green">${role} view</span><span>Frontend simulation · data is for demonstration only</span></div>
    ${role === 'Admin' || role === 'Manager' ? opsCards() : `<div class="metric-grid">
      ${[
        ['Total sales', '₱248,560', '↑ 12.8%', 'vs. last month', 'green-icon', '◒'],
        ['Total profit', '₱96,482', '↑ 8.4%', 'vs. last month', 'orange-icon', '◉'],
        ['Total food cost', '₱61,290', '24.7%', 'of total sales', 'purple-icon', '◌'],
        ['Menu items', '24', '+ 3', 'this month', 'red-icon', '✦']
      ].map(([label,value,change,foot,icon,mark]) => `<div class="metric-card"><div class="metric-top"><span>${label}</span><i class="metric-icon ${icon}">${mark}</i></div><div class="metric-value">${value}</div><div class="metric-foot"><b class="${change.includes('↑') || change.includes('+') ? 'up' : ''}">${change}</b> ${foot}</div></div>`).join('')}</div>`}
    <div class="dashboard-grid">
      <div class="panel"><div class="panel-header"><div><div class="panel-title">Sales overview</div><div class="panel-subtitle">Track your revenue performance over time</div></div><div><select class="select-small"><option>Last 30 days</option><option>Last 7 days</option></select></div></div><div class="chart-wrap">${svgChart()}</div><div class="legend"><span class="sales">Sales</span><span class="cost">Food cost</span><span class="profit">Profit</span></div></div>
      <div class="panel"><div class="panel-header"><div><div class="panel-title">Most profitable dishes</div><div class="panel-subtitle">Based on profit per serving</div></div><span class="view-link">View all →</span></div><div class="insight-list">
        ${data.dishes.slice(0,3).map((d,i)=>`<div class="insight-item"><div class="dish-thumb">${d.emoji}</div><div class="insight-copy"><strong>${d.name}</strong><span>${d.sold} orders this month</span></div><div class="profit-amount">${money(d.price-d.cost)}<small>per serving</small></div></div>`).join('')}
      </div></div>
    </div>
    <div class="bottom-grid">
      <div class="panel"><div class="panel-header"><div><div class="panel-title">Inventory watchlist</div><div class="panel-subtitle">Ingredients that need your attention</div></div><span class="view-link" data-go="inventory">View inventory →</span></div>
        ${data.ingredients.filter(i=>i.tone!=='good').map(i=>`<div class="stock-row"><div class="stock-name">${i.emoji} &nbsp;${i.name}<span>${i.stock} remaining · reorder at ${i.reorder}</span></div><div class="stock-level"><div class="level-track"><div class="level-bar ${i.tone}" style="width:${i.percent}%"></div></div></div><div class="stock-status ${i.tone}-text">${i.status}</div></div>`).join('')}
      </div>
      <div class="panel"><div class="panel-header"><div><div class="panel-title">Profit trend</div><div class="panel-subtitle">Net profit vs. food cost</div></div><select class="select-small"><option>May 2024</option></select></div><div class="chart-wrap">${svgChart().replaceAll('sales-line','sales-line').replaceAll('sales-area','sales-area')}</div></div>
    </div>`;
}

function menuView() {
  return `${header('Menu management', 'Keep your menu, prices, and availability up to date.')}
    <div class="toolbar"><input class="search-box" placeholder="⌕  Search menu items..." /><div class="spacer"></div><button class="ghost-btn">☷ Filter</button><button class="ghost-btn">⇅ Sort</button></div>
    <div class="card-grid">${data.dishes.map(d=>`<div class="panel menu-card"><div class="menu-card-top"><div class="menu-food">${d.emoji}</div><span class="pill ${d.status === 'Available' ? 'green' : 'orange'}">● ${d.status}</span></div><h3>${d.name}</h3><p>${d.category} · ${d.sold} sold this month</p><div class="menu-card-footer"><span class="menu-price">${money(d.price)}</span><span class="view-link">View recipe →</span></div></div>`).join('')}</div>`;
}

function recipesView() {
  return `${header('Recipe management', 'Build consistent recipes and understand the true cost of every dish.')}
    <div class="detail-grid"><div class="panel"><div class="panel-header"><div><div class="panel-title">Your recipes</div><div class="panel-subtitle">5 active recipes</div></div><span class="view-link">＋ Add recipe</span></div>${data.dishes.map((d,i)=>`<div class="recipe-item"><div class="dish-thumb">${d.emoji}</div><div><strong>${d.name}</strong><small>${i+3} ingredients · updated 2 days ago</small></div><span class="recipe-qty">${money(d.cost)}</span></div>`).join('')}</div>
    <div class="panel"><div class="panel-header"><div><div class="panel-title">Chicken Adobo</div><div class="panel-subtitle">Recipe breakdown · 1 serving</div></div><span class="pill green">Active</span></div><div class="recipe-list">${[['🍗','Chicken','500 g','₱48.00'],['🥣','Soy sauce','100 ml','₱7.50'],['🫗','Vinegar','50 ml','₱3.25'],['🧄','Garlic','20 g','₱4.40'],['🌿','Bay leaf & spices','1 portion','₱1.35']].map(r=>`<div class="recipe-item"><div class="ingredient-icon">${r[0]}</div><div><strong>${r[1]}</strong><small>Cost per batch</small></div><span class="recipe-qty">${r[2]} &nbsp; <b>${r[3]}</b></span></div>`).join('')}</div><div class="cost-breakdown"><div class="cost-line"><span>Ingredient cost</span><b>₱64.50</b></div><div class="cost-line"><span>Packaging cost</span><b>₱5.00</b></div><div class="cost-line total"><span>Total food cost</span><b>₱69.50</b></div></div></div></div>`;
}

function inventoryView() {
  return `${header('Ingredient inventory', 'Know what is in stock, what is running low, and what to order next.','＋ Add ingredient')}
    <div class="metric-grid"><div class="metric-card"><div class="metric-top"><span>Total ingredients</span><i class="metric-icon green-icon">▤</i></div><div class="metric-value">42</div><div class="metric-foot">Across 3 storage areas</div></div><div class="metric-card"><div class="metric-top"><span>Low stock</span><i class="metric-icon red-icon">!</i></div><div class="metric-value">3</div><div class="metric-foot"><b class="down">Needs attention</b> today</div></div><div class="metric-card"><div class="metric-top"><span>Inventory value</span><i class="metric-icon purple-icon">◉</i></div><div class="metric-value">₱38,420</div><div class="metric-foot">Current stock value</div></div><div class="metric-card"><div class="metric-top"><span>Last updated</span><i class="metric-icon orange-icon">↻</i></div><div class="metric-value">Today</div><div class="metric-foot">09:42 AM by Jamie</div></div></div>
    <div class="panel"><div class="panel-header"><div><div class="panel-title">All ingredients</div><div class="panel-subtitle">Real-time stock levels and reorder thresholds</div></div><div class="toolbar" style="margin:0"><button class="ghost-btn">☷ All categories</button><button class="primary-btn">Export report</button></div></div><div class="table-wrap"><table class="data-table"><thead><tr><th>Ingredient name</th><th>Current stock</th><th>Unit cost</th><th>Reorder level</th><th>Stock health</th><th>Action</th></tr></thead><tbody>${data.ingredients.map(i=>`<tr><td><div class="dish-cell"><div class="mini-food">${i.emoji}</div>${i.name}<small style="color:#99a59f;margin-left:3px">/ ${i.unit}</small></div></td><td>${i.stock}</td><td>${money(i.cost)}</td><td>${i.reorder}</td><td><span class="pill ${i.tone==='good'?'green':i.tone==='warn'?'orange':'red'}">${i.status}</span></td><td><span class="view-link">•••</span></td></tr>`).join('')}</tbody></table></div></div>`;
}

function analysisView() {
  return `${header('Sales & profit analysis', 'See which dishes are driving margin and which need a closer look.','Export report')}
  <div class="panel"><div class="panel-header"><div><div class="panel-title">Dish profitability</div><div class="panel-subtitle">May 01 – May 31, 2024 · 842 dishes sold</div></div><div class="toolbar" style="margin:0"><button class="ghost-btn">☷ Filter</button><select class="select-small"><option>All categories</option></select></div></div><div class="table-wrap"><table class="data-table"><thead><tr><th>Dish sold</th><th>Quantity sold</th><th>Selling price</th><th>Food cost</th><th>Profit</th><th>Profit margin</th></tr></thead><tbody>${data.dishes.map((d,i)=>{let profit=d.price-d.cost;let margin=Math.round(profit/d.price*100);return `<tr><td><div class="dish-cell"><div class="mini-food">${d.emoji}</div>${d.name}</div></td><td>${d.sold}</td><td>${money(d.price)}</td><td>${money(d.cost)}</td><td><b style="color:${margin>60?'var(--teal)':'var(--red)'}">${money(profit)}</b></td><td><span class="pill ${margin>60?'green':'orange'}">${margin}% ${margin>60?'High profit':'Watch'}</span></td></tr>`}).join('')}</tbody></table></div></div>`;
}

function reportsView() {
  return `${header('Reports', 'Visual summaries to help you make confident decisions, faster.')}
  <div class="report-grid">${[['◒','Daily sales report','₱15,420 revenue · 48 completed orders'],['◒','Weekly sales report','₱82,640 revenue · 312 orders'],['◒','Monthly sales report','₱328,000 revenue · 1,254 orders'],['◌','Food cost report','See cost breakdown by menu item.'],['↗','Product performance','Burger is the best seller this month.'],['▤','Inventory report','3 ingredients need restocking.']].map(r=>`<div class="panel report-card"><div class="report-icon">${r[0]}</div><strong>${r[1]}</strong><span>${r[2]}</span><button>View report →</button></div>`).join('')}</div>
  <div class="panel" style="margin-top:18px"><div class="panel-header"><div><div class="panel-title">Monthly performance summary</div><div class="panel-subtitle">A quick visual view of your business health</div></div><button class="ghost-btn">⇩ Export PDF</button></div><div class="chart-wrap">${svgChart()}</div></div>`;
}

function calculatorView() {
  return `${header('Food cost calculator', 'Understand the real cost of preparing each item on your menu.')}
  <div class="panel"><div class="panel-header"><div><div class="panel-title">Cost per serving</div><div class="panel-subtitle">Ingredient, packaging, and labor costs combined</div></div><button class="ghost-btn">＋ Add dish</button></div><div class="table-wrap"><table class="data-table"><thead><tr><th>Dish</th><th>Ingredient cost</th><th>Packaging</th><th>Labor</th><th>Total food cost</th><th>Cost / serving</th></tr></thead><tbody>${data.dishes.map((d,i)=>`<tr><td><div class="dish-cell"><div class="mini-food">${d.emoji}</div>${d.name}</div></td><td>${money(d.cost)}</td><td>₱${[5,6,5,4,5][i]}.00</td><td>₱${[12,15,13,8,14][i]}.00</td><td><b>${money(d.cost+[17,21,18,12,19][i])}</b></td><td><span class="pill green">${money(d.cost+[17,21,18,12,19][i])}</span></td></tr>`).join('')}</tbody></table></div></div>`;
}

function opsCards() {
  return `<div class="metric-grid">${[['Total orders','1,254','↑ 12.4%','Today'],['Daily sales','₱15,420','↑ 8.7%','vs yesterday'],['Monthly sales','₱328,000','↑ 14.2%','this month'],['Active orders',workflow.orders.filter(o=>o.status!=='Completed').length,'Live now','in kitchen'],['Available stocks','542','92%','healthy items'],['Completed orders','1,198','↑ 11.5%','this month']].map((m,i)=>`<div class="metric-card"><div class="metric-top"><span>${m[0]}</span><i class="metric-icon ${['green-icon','orange-icon','purple-icon','red-icon'][i%4]}">${['◒','◉','◌','✦'][i%4]}</i></div><div class="metric-value">${m[1]}</div><div class="metric-foot"><b class="${i===3?'down':'up'}">${m[2]}</b> ${m[3]}</div></div>`).join('')}</div>`;
}

function orderStatusChip(status) {
  return `<span class="pill ${status==='Ready'?'green':status==='Preparing'?'orange':'red'}">${status}</span>`;
}

function workflowRows() {
  return workflow.orders.map(order => `<div class="order-row"><div><strong>Order #${order.id}</strong><span>Table #${order.table} · ${order.items.map(i=>`${i[1]}× ${i[0]}`).join(', ')}</span></div>${orderStatusChip(order.status)}<b>${money(order.total)}</b></div>`).join('');
}

function posView() {
  const total = workflow.cart.reduce((sum, item) => sum + item.price * item.qty, 0);
  return `${header('Point of Sale', 'Create orders quickly and keep service moving.','＋ New order')}
    <div class="pos-layout"><div class="panel pos-menu"><div class="panel-header"><div><div class="panel-title">Quick order</div><div class="panel-subtitle">Tap a product to add it to the current order</div></div><span class="pill green">● Register open</span></div><div class="category-tabs"><button class="category-tab active">All items</button><button class="category-tab">Main Course</button><button class="category-tab">Snacks</button><button class="category-tab">Drinks</button></div><div class="pos-product-grid">${posProducts.map(p=>`<button class="pos-product" data-add-product="${p[0]}"><span>${p[1]}</span><strong>${p[0]}</strong><small>${p[3]}</small><b>${money(p[2])}</b></button>`).join('')}</div></div>
    <div class="panel order-summary"><div class="panel-header"><div><div class="panel-title">Current order</div><div class="panel-subtitle">Order #${workflow.nextOrder} · Table 5</div></div><button class="clear-cart">Clear</button></div><div class="cart-items">${workflow.cart.length ? workflow.cart.map((item,i)=>`<div class="cart-item"><div class="mini-food">${posProducts.find(p=>p[0]===item.name)?.[1] || '🍽️'}</div><div><strong>${item.name}</strong><small>${money(item.price)} each</small></div><div class="qty-control"><button data-qty="${i}" data-step="-1">−</button><b>${item.qty}</b><button data-qty="${i}" data-step="1">＋</button></div><b>${money(item.price*item.qty)}</b></div>`).join('') : '<div class="empty-state">Your order is empty<br><small>Choose items to get started</small></div>'}</div><div class="order-total"><span>Subtotal</span><b>${money(total)}</b></div><div class="order-total"><span>Service charge <small>5%</small></span><b>${money(total*.05)}</b></div><div class="order-grand"><span>Total</span><b>${money(total*1.05)}</b></div><div class="payment-label">Payment method</div><div class="payment-buttons">${['Cash','GCash','Card'].map(p=>`<button class="${workflow.selectedPayment===p?'selected':''}" data-payment="${p}">${p}</button>`).join('')}</div><button class="primary-btn submit-order" ${workflow.cart.length?'':'disabled'}>Submit order · ${money(total*1.05)}</button></div></div>
    <div class="pos-lower"><div class="panel order-history"><div class="panel-header"><div><div class="panel-title">Today's transactions</div><div class="panel-subtitle">Live order activity across the restaurant</div></div><span class="view-link">View all →</span></div>${workflowRows()}</div><div class="panel receipt-panel"><div class="ready-notice">🔔 <strong>Order #1001 is Ready for Serving</strong><span>Kitchen marked it ready · Table #5</span></div><div class="receipt"><div class="receipt-brand">BASIL &amp; ASH<small>Restaurant &amp; Café</small></div><div class="receipt-line"><span>Order #1001</span><span>Today, 12:42 PM</span></div>${[['Burger','2','₱440'],['Fries','1','₱70'],['Coke','2','₱70']].map(i=>`<div class="receipt-item"><span>${i[0]} × ${i[1]}</span><b>${i[2]}</b></div>`).join('')}<div class="receipt-total"><span>Total</span><b>₱580</b></div><div class="receipt-paid"><span>Paid · Cash</span><b>₱600</b></div><div class="receipt-change"><span>Change</span><b>₱20</b></div></div><button class="primary-btn serve-order">Mark as served &amp; paid</button></div></div>`;
}

function kitchenView() {
  const columns = ['Pending', 'Preparing', 'Ready'];
  return `${header('Kitchen monitor', 'A clear view of every order, from ticket to service.','Kitchen display')}
    <div class="kitchen-banner"><span class="live-dot"></span><strong>Kitchen is live</strong><span>Orders update instantly in this presentation simulation</span><b>${workflow.orders.length} active tickets</b></div>
    <div class="kanban">${columns.map(status=>`<div class="kanban-column"><div class="kanban-heading"><h3>${status}</h3><span>${workflow.orders.filter(o=>o.status===status).length}</span></div>${workflow.orders.filter(o=>o.status===status).map(order=>`<div class="kitchen-card"><div class="kitchen-card-top"><strong>Order #${order.id}</strong><span>Table #${order.table}</span></div><div class="kitchen-items">${order.items.map(i=>`<div><span>${i[1]}×</span>${i[0]}</div>`).join('')}</div><div class="kitchen-card-footer"><small>Received 4 min ago</small>${status==='Pending'?`<button class="primary-btn kitchen-action" data-order="${order.id}" data-next="Preparing">Start preparing</button>`:status==='Preparing'?`<button class="primary-btn kitchen-action" data-order="${order.id}" data-next="Ready">Mark ready</button>`:`<span class="ready-label">✓ Ready to serve</span>`}</div></div>`).join('') || '<div class="empty-column">No orders here</div>'}</div>`).join('')}</div>`;
}

function managerView() {
  return `${header('Manager insights', 'See the business behind every order and make faster decisions.','Export insights')}
    ${opsCards()}<div class="dashboard-grid"><div class="panel"><div class="panel-header"><div><div class="panel-title">Revenue trends</div><div class="panel-subtitle">Daily, weekly, and monthly revenue performance</div></div><select class="select-small"><option>Last 30 days</option></select></div><div class="chart-wrap">${svgChart()}</div></div><div class="panel"><div class="panel-header"><div><div class="panel-title">Peak sales hours</div><div class="panel-subtitle">When your restaurant is busiest</div></div></div><div class="hour-bars">${[['12 PM',82],['1 PM',96],['6 PM',64],['7 PM',88],['8 PM',72]].map(h=>`<div class="hour-bar"><span>${h[0]}</span><div><i style="width:${h[1]}%"></i></div><b>${h[1]}%</b></div>`).join('')}</div></div></div>
    <div class="bottom-grid"><div class="panel"><div class="panel-header"><div><div class="panel-title">Most ordered products</div><div class="panel-subtitle">Volume by item this month</div></div></div>${[['🍔','Burger','342 orders'],['🍗','Chicken Meal','286 orders'],['🍟','Fries','241 orders'],['🍝','Spaghetti','198 orders']].map((x,i)=>`<div class="stock-row"><div class="dish-thumb">${x[0]}</div><div class="stock-name">${x[1]}<span>${x[2]}</span></div><div class="stock-level"><div class="level-track"><div class="level-bar good" style="width:${92-i*14}%"></div></div></div><b class="good-text">${money([75240,74360,16870,38610][i])}</b></div>`).join('')}</div><div class="panel"><div class="panel-header"><div><div class="panel-title">Business KPIs</div><div class="panel-subtitle">Operational snapshot</div></div></div><div class="kpi-list"><div><span>Total revenue</span><b>₱328,000</b></div><div><span>Average order value</span><b>₱264</b></div><div><span>Customer traffic</span><b>1,842</b></div><div><span>Completed orders</span><b>1,198</b></div></div></div></div>`;
}

function adminView() {
  return `${header('Admin center', 'Manage the restaurant setup, people, and system performance.','＋ Add product')}
    ${opsCards()}<div class="admin-grid"><div class="panel"><div class="panel-header"><div><div class="panel-title">Menu & categories</div><div class="panel-subtitle">6 products · 4 categories</div></div><button class="ghost-btn">Manage categories</button></div><div class="table-wrap"><table class="data-table"><thead><tr><th>Product</th><th>Category</th><th>Price</th><th>Status</th><th>Action</th></tr></thead><tbody>${[['🍔','Burger','Main Course','₱220'],['🍗','Chicken Meal','Main Course','₱260'],['🍝','Spaghetti','Main Course','₱195'],['🍟','Fries','Snacks','₱70'],['🥤','Soft Drinks','Drinks','₱35'],['🍧','Halo-Halo','Desserts','₱145']].map(p=>`<tr><td><div class="dish-cell"><div class="mini-food">${p[0]}</div>${p[1]}</div></td><td>${p[2]}</td><td>${p[3]}</td><td><span class="pill green">Active</span></td><td><span class="view-link">Edit · Archive</span></td></tr>`).join('')}</tbody></table></div></div><div class="panel"><div class="panel-header"><div><div class="panel-title">System statistics</div><div class="panel-subtitle">Today at a glance</div></div></div><div class="kpi-list"><div><span>Active users</span><b>12</b></div><div><span>Kitchen tickets</span><b>${workflow.orders.length}</b></div><div><span>Low stock alerts</span><b class="down">3</b></div><div><span>System status</span><b class="good-text">Healthy</b></div></div><div class="admin-users"><strong>Team access</strong><span>Jamie Dela Cruz · Admin</span><span>Marco Santos · Cashier</span><span>Ana Reyes · Kitchen Staff</span><span>Rina Cruz · Inventory Staff</span></div></div></div>`;
}

const views = { dashboard, pos: posView, kitchen: kitchenView, manager: managerView, admin: adminView, menu: menuView, recipes: recipesView, inventory: inventoryView, calculator: calculatorView, analysis: analysisView, reports: reportsView };
const roleModules = {
  Admin: ['dashboard', 'admin', 'pos', 'kitchen', 'manager', 'menu', 'recipes', 'inventory', 'calculator', 'analysis', 'reports'],
  Cashier: ['dashboard', 'pos', 'menu', 'analysis'],
  'Kitchen Staff': ['dashboard', 'kitchen', 'recipes', 'inventory'],
  Manager: ['dashboard', 'manager', 'pos', 'kitchen', 'menu', 'inventory', 'analysis', 'reports'],
  'Inventory Staff': ['dashboard', 'inventory', 'recipes', 'reports']
};
function applyRoleAccess() {
  const allowed = roleModules[role];
  document.querySelectorAll('[data-view]').forEach(btn => {
    btn.hidden = !allowed.includes(btn.dataset.view);
  });
  const sidebarRole = document.querySelector('.user-mini div:nth-child(2) span');
  if (sidebarRole) sidebarRole.textContent = role;
  const badge = document.querySelector('.order-badge');
  if (badge) badge.textContent = workflow.orders.filter(order => order.status !== 'Completed').length;
}
function wireView() {
  document.querySelectorAll('[data-add-product]').forEach(button => button.addEventListener('click', () => {
    const product = posProducts.find(item => item[0] === button.dataset.addProduct);
    const existing = workflow.cart.find(item => item.name === product[0]);
    if (existing) existing.qty += 1;
    else workflow.cart.push({ name: product[0], price: product[2], qty: 1 });
    render('pos');
  }));
  document.querySelectorAll('[data-qty]').forEach(button => button.addEventListener('click', () => {
    const item = workflow.cart[Number(button.dataset.qty)];
    item.qty += Number(button.dataset.step);
    if (item.qty <= 0) workflow.cart.splice(Number(button.dataset.qty), 1);
    render('pos');
  }));
  document.querySelectorAll('[data-payment]').forEach(button => button.addEventListener('click', () => { workflow.selectedPayment = button.dataset.payment; render('pos'); }));
  document.querySelector('.clear-cart')?.addEventListener('click', () => { workflow.cart = []; render('pos'); });
  document.querySelector('.submit-order')?.addEventListener('click', () => {
    const total = workflow.cart.reduce((sum, item) => sum + item.price * item.qty, 0) * 1.05;
    workflow.orders.unshift({ id: workflow.nextOrder++, table: 5, items: workflow.cart.map(item => [item.name, item.qty]), status: 'Pending', total, payment: 'Pending' });
    workflow.cart = [];
    render('pos');
    alert('Order submitted to the kitchen queue.');
  });
  document.querySelector('.serve-order')?.addEventListener('click', () => {
    const order = workflow.orders.find(item => item.id === 1001);
    if (order) { order.status = 'Completed'; order.payment = 'Paid'; }
    render('pos');
  });
  document.querySelectorAll('.kitchen-action').forEach(button => button.addEventListener('click', () => {
    const order = workflow.orders.find(item => item.id === Number(button.dataset.order));
    order.status = button.dataset.next;
    render('kitchen');
    if (order.status === 'Ready') alert(`🔔 Order #${order.id} is Ready for Serving`);
  }));
  document.querySelectorAll('.primary-btn,.report-card button').forEach(btn => btn.addEventListener('click', () => {
    if (btn.textContent.includes('Export') || btn.textContent.includes('report') || btn.textContent.includes('insights')) alert('Export is a presentation-only demo action.');
  }));
}
function render(view = 'dashboard') {
  app.innerHTML = views[view]();
  pageCrumb.textContent = view === 'dashboard' ? 'Overview' : view[0].toUpperCase()+view.slice(1);
  document.querySelectorAll('[data-view]').forEach(btn => btn.classList.toggle('active', btn.dataset.view === view));
  document.querySelectorAll('[data-go]').forEach(el => el.addEventListener('click', () => { render(el.dataset.go); }));
  applyRoleAccess();
  wireView();
}
document.querySelectorAll('[data-view]').forEach(btn => btn.addEventListener('click', () => { render(btn.dataset.view); document.querySelector('#sidebar').classList.remove('open'); }));
document.querySelector('#roleSelect').addEventListener('change', e => { role = e.target.value; render('dashboard'); });
document.querySelector('#mobileMenu').addEventListener('click', () => document.querySelector('#sidebar').classList.toggle('open'));
render();
