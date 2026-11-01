const SUPABASE_URL = 'https://niiodqunoflblfcgdods.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_IVE25Rqzu-lDLFayVYmhfQ_dvPIO6E5';

window.supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY,
  { auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true } }
);

const recordVersions = new Map();
const tableForCollection = {
  ingredients: 'ingredients',
  recipes: 'recipes',
  inventoryTransactions: 'inventory_transactions',
  productionLogs: 'production_logs',
  revenueRecords: 'revenue_records',
  wasteLogs: 'waste_logs',
  physicalCounts: 'physical_counts',
  users: 'profiles',
  reservations: 'reservations',
  restaurantTables: 'restaurant_tables'
};

function rememberVersion(collection, id, updatedAt) {
  if (updatedAt) recordVersions.set(`${collection}:${id}`, updatedAt);
}

function dateValue(value) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString().slice(0, 10);
}

function mapDatabaseRecord(collection, row) {
  const updatedAt = row.updated_at;
  if (collection === 'users') {
    rememberVersion(collection, row.id, updatedAt);
    return { id: row.id, name: row.full_name, email: row.email, role: row.role };
  }
  rememberVersion(collection, row.id, updatedAt);
  if (collection === 'recipes') {
    return {
      id: row.id, name: row.name, category: row.category, price: Number(row.price),
      wastage: Number(row.wastage),
      ingredients: (row.recipe_ingredients || []).map(line => ({
        ingredientId: line.ingredient_id, quantity: Number(line.quantity)
      }))
    };
  }
  if (collection === 'inventoryTransactions') {
    return {
      id: row.id, ingredientId: row.ingredient_id, quantity: Number(row.quantity),
      unitCost: Number(row.unit_cost), date: row.transaction_date,
      type: row.transaction_type, note: row.note || ''
    };
  }
  if (collection === 'productionLogs') {
    return { id: row.id, recipeId: row.recipe_id, quantity: Number(row.quantity), date: row.production_date, mode: row.mode };
  }
  if (collection === 'wasteLogs') {
    return { id: row.id, ingredientId: row.ingredient_id, quantity: Number(row.quantity), reason: row.reason, date: row.waste_date };
  }
  if (collection === 'physicalCounts') {
    return { id: row.id, ingredientId: row.ingredient_id, expected: Number(row.expected), actual: Number(row.actual), date: row.count_date };
  }
  if (collection === 'revenueRecords') {
    return window.CostTrackLogic.createRevenueRecord({
      id: row.id, business_date: row.business_date, meal_period: row.meal_period,
      adult_customers: row.adult_customers, adult_rate: Number(row.adult_rate),
      child_customers: row.child_customers, child_rate: Number(row.child_rate),
      senior_pwd_customers: row.senior_pwd_customers, senior_pwd_rate: Number(row.senior_pwd_rate),
      status: row.status, remarks: row.remarks, recorded_by: row.recorded_by,
      recorded_at: row.recorded_at, last_edited_by: row.last_edited_by,
      last_edited_at: row.last_edited_at, edit_reason: row.edit_reason,
      voided_by: row.voided_by, void_reason: row.void_reason, voided_at: row.voided_at
    });
  }
  if (collection === 'reservations') {
    return {
      id: row.id, name: row.name, email: row.email, phone: row.phone,
      date: row.reservation_date, time: row.reservation_time, guests: row.guests,
      adults: row.adults, children: row.children, occasion: row.occasion,
      status: row.status, preference: row.preference, request: row.request,
      table: row.table_id, estimatedRevenue: Number(row.estimated_revenue || 0)
    };
  }
  if (collection === 'restaurantTables') {
    return { id: row.id, seats: row.seats, status: row.status, x: Number(row.x), y: Number(row.y), guest: row.guest };
  }
  return {
    id: row.id, name: row.name, category: row.category, unit: row.unit,
    cost: Number(row.cost), stock: Number(row.stock), minimum: Number(row.minimum)
  };
}

function mapApplicationRecord(collection, record) {
  if (collection === 'ingredients') return { id: record.id, name: record.name, category: record.category, unit: record.unit, cost: record.cost, stock: record.stock, minimum: record.minimum };
  if (collection === 'recipes') return { id: record.id, name: record.name, category: record.category, price: record.price, wastage: record.wastage, ingredients: record.ingredients };
  if (collection === 'inventoryTransactions') return { id: record.id, ingredient_id: record.ingredientId, quantity: record.quantity, unit_cost: record.unitCost, transaction_date: dateValue(record.date), transaction_type: record.type, note: record.note || '' };
  if (collection === 'productionLogs') return { id: record.id, recipe_id: record.recipeId, quantity: record.quantity, production_date: dateValue(record.date), mode: record.mode };
  if (collection === 'wasteLogs') return { id: record.id, ingredient_id: record.ingredientId, quantity: record.quantity, reason: record.reason, waste_date: dateValue(record.date) };
  if (collection === 'physicalCounts') return { id: record.id, ingredient_id: record.ingredientId, expected: record.expected, actual: record.actual, count_date: dateValue(record.date) };
  if (collection === 'revenueRecords') return {
    id: record.id, business_date: dateValue(record.business_date), meal_period: record.meal_period,
    adult_customers: record.adult_customers, adult_rate: record.adult_rate,
    child_customers: record.child_customers, child_rate: record.child_rate,
    senior_pwd_customers: record.senior_pwd_customers, senior_pwd_rate: record.senior_pwd_rate,
    status: record.status, remarks: record.remarks || '', recorded_by: record.recorded_by || '',
    recorded_at: record.recorded_at || new Date().toISOString(), last_edited_by: record.last_edited_by || '',
    last_edited_at: record.last_edited_at || null, edit_reason: record.edit_reason || '',
    voided_by: record.voided_by || '', void_reason: record.void_reason || '', voided_at: record.voided_at || null
  };
  if (collection === 'reservations') return {
    id: record.id, name: record.name, email: record.email || '', phone: record.phone || '',
    reservation_date: dateValue(record.date), reservation_time: record.time, guests: Number(record.guests || 0),
    adults: record.adults === undefined ? Number(record.guests || 0) : Number(record.adults), children: Number(record.children || 0),
    occasion: record.occasion || '', status: record.status || 'Pending', preference: record.preference || '',
    request: record.request || record.requests || '', table_id: record.table || null,
    estimated_revenue: Number(record.estimatedRevenue || 0)
  };
  if (collection === 'restaurantTables') return { id: record.id, seats: record.seats, status: record.status, x: record.x, y: record.y, guest: record.guest || '' };
  return { id: record.id, name: record.name, category: record.category, unit: record.unit, cost: record.cost, stock: record.stock, minimum: record.minimum };
}

function throwIfError(error) {
  if (error) throw new Error(error.message || 'The database operation failed.');
}

window.supabaseRecord = {
  async load(collection) {
    const table = tableForCollection[collection];
    if (!table) throw new Error(`Unknown data collection: ${collection}`);
    const client = window.supabaseClient;
    let result;
    if (collection === 'users') {
      result = await client.from('profiles').select('id,email,full_name,role,updated_at').order('full_name');
    } else if (collection === 'recipes') {
      result = await client.from(table).select('id,name,category,price,wastage,updated_at,recipe_ingredients(ingredient_id,quantity)').order('name');
    } else {
      result = await client.from(table).select('*');
    }
    throwIfError(result.error);
    return (result.data || []).map(row => mapDatabaseRecord(collection, row));
  },
  async upsert(collection, record, expectedVersion) {
    if (collection === 'users') throw new Error('User accounts must be provisioned through Supabase Auth.');
    const table = tableForCollection[collection];
    if (!table) throw new Error(`Unknown data collection: ${collection}`);
    const row = mapApplicationRecord(collection, record);
    const dateColumn = {
      inventoryTransactions: 'transaction_date', productionLogs: 'production_date',
      wasteLogs: 'waste_date', physicalCounts: 'count_date',
      revenueRecords: 'business_date', reservations: 'reservation_date'
    }[collection];
    if (dateColumn && !row[dateColumn]) throw new Error('Enter a valid date before saving.');
    const versionKey = `${collection}:${record.id}`;
    const storedVersion = recordVersions.get(versionKey);
    const version = expectedVersion === undefined ? storedVersion : expectedVersion;
    let result;
    if (collection === 'recipes') {
      if (version == null && storedVersion) throw new Error('This recipe changed in another session. Reload the page before saving your change.');
      const { data, error } = await window.supabaseClient.rpc('save_recipe', {
        payload: {
          ...row,
          ingredients: row.ingredients.map(line => ({
            ingredient_id: line.ingredientId,
            quantity: line.quantity
          }))
        },
        expected_updated_at: version || null
      });
      throwIfError(error);
      if (data?.updated_at) rememberVersion(collection, record.id, data.updated_at);
      return;
    }
    if (version) {
      result = await window.supabaseClient.from(table).update(row).eq('id', record.id).eq('updated_at', version).select('updated_at').maybeSingle();
      throwIfError(result.error);
      if (!result.data) throw new Error('This record changed in another session. Reload the page before saving your change.');
    } else {
      if (storedVersion) throw new Error('This record changed in another session. Reload the page before saving your change.');
      result = await window.supabaseClient.from(table).insert(row).select('updated_at').single();
      throwIfError(result.error);
    }
    rememberVersion(collection, record.id, result.data.updated_at);
  },
  async remove(collection, recordId, expectedVersion) {
    if (collection === 'users') throw new Error('User accounts must be managed through Supabase Auth.');
    const table = tableForCollection[collection];
    if (!table) throw new Error(`Unknown data collection: ${collection}`);
    const storedVersion = recordVersions.get(`${collection}:${recordId}`);
    const version = expectedVersion === undefined ? storedVersion : expectedVersion;
    if (version == null && storedVersion) throw new Error('This record changed in another session. Reload the page before deleting it.');
    let request = window.supabaseClient.from(table).delete().eq('id', recordId);
    if (version) request = request.eq('updated_at', version);
    const { data, error } = await request.select('id');
    throwIfError(error);
    if (!data?.length) throw new Error('This record changed or is no longer available. Reload the page and try again.');
    recordVersions.delete(`${collection}:${recordId}`);
  },
  async submitPublicReservation(payload) {
    const { data, error } = await window.supabaseClient.rpc('public_create_reservation', {
      payload: {
        ...payload,
        reservation_date: payload.date,
        reservation_time: payload.time,
        adults: payload.adults ?? payload.guests,
        children: payload.children ?? 0
      }
    });
    throwIfError(error);
    return data;
  },
  async getPublicReservationStatus(reference, contact) {
    const { data, error } = await window.supabaseClient.rpc('public_get_reservation_status', {
      reference,
      contact
    });
    throwIfError(error);
    return data;
  },
  version(collection, recordId) {
    return recordVersions.get(`${collection}:${recordId}`) || null;
  },
  clearVersions() {
    recordVersions.clear();
  }
};
