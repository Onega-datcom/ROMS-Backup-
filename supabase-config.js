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
  restaurantTables: 'restaurant_tables',
  buffetRates: 'buffet_rates'
};

function rememberVersion(collection, id, updatedAt) {
  if (updatedAt) recordVersions.set(`${collection}:${id}`, updatedAt);
}

function dateValue(value) {
  const str = String(value || '');
  if (/^\d{4}-\d{2}-\d{2}$/.test(str)) return str;
  const parsed = new Date(str);
  if (Number.isNaN(parsed.getTime())) return null;
  return `${parsed.getFullYear()}-${String(parsed.getMonth() + 1).padStart(2, '0')}-${String(parsed.getDate()).padStart(2, '0')}`;
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
      id: row.id, name: row.name, category: row.category,
      price: row.menu_price == null ? null : Number(row.menu_price),
      wastage: row.wastage == null ? null : Number(row.wastage),
      batchYield: Number(row.batch_yield || 30),
      prepTarget: Number(row.prep_target || 30),
      prepNotes: row.prep_notes || '',
      ingredients: (row.recipe_ingredients || row.ingredients || []).map(line => ({
        ingredientId: line.ingredient_id, quantity: Number(line.quantity)
      }))
    };
  }
  if (collection === 'inventoryTransactions') {
    return {
      id: row.id, ingredientId: row.ingredient_id, quantity: Number(row.quantity),
      unitCost: Number(row.unit_cost), date: row.transaction_date,
      type: row.transaction_type, note: row.note || '',
      supplierName: row.supplier_name || '', invoiceNumber: row.invoice_number || '',
      invoiceDate: row.invoice_date || '', batchCode: row.batch_code || '',
      expirationDate: row.expiration_date || ''
    };
  }
  if (collection === 'productionLogs') {
    return { id: row.id, recipeId: row.recipe_id, quantity: Number(row.quantity), coversProduced: row.covers_produced == null ? null : Number(row.covers_produced), date: row.production_date, mode: row.mode };
  }
  if (collection === 'wasteLogs') {
    return {
      id: row.id, ingredientId: row.ingredient_id, quantity: Number(row.quantity),
      reason: row.reason, date: row.waste_date, productionLogId: row.production_log_id || null,
      recordedAt: row.recorded_at || null, recordedBy: row.recorded_by || null, notes: row.notes || ''
    };
  }
  if (collection === 'physicalCounts') {
    return { id: row.id, ingredientId: row.ingredient_id, expected: Number(row.expected), actual: Number(row.actual), date: row.count_date };
  }
  if (collection === 'revenueRecords') {
    return window.CostTrackLogic.createRevenueRecord({
      id: row.id, business_date: row.business_date, meal_period: row.meal_period,
      reservation_id: row.reservation_id,
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
      table: row.table_id, type: row.type, seatedAt: row.seated_at, completedAt: row.completed_at,
      actualCovers: row.actual_covers, correctionReason: row.last_correction_reason || ''
    };
  }
  if (collection === 'restaurantTables') {
    return {
      id: row.id, seats: row.seats, tableType: row.table_type || 'Unassigned',
      area: row.area || 'Unassigned', status: row.status,
      x: Number(row.x), y: Number(row.y), guest: row.guest
    };
  }
  if (collection === 'buffetRates') {
    return { id: row.id, mealPeriod: row.meal_period, dayType: row.day_type,
      adultRate: Number(row.adult_rate), childRate: Number(row.child_rate),
      seniorPwdRate: Number(row.senior_pwd_rate), effectiveFrom: row.effective_from,
      effectiveTo: row.effective_to, isActive: row.is_active };
  }
  return {
    id: row.id, name: row.name, category: row.category, unit: row.unit,
    cost: row.cost == null ? null : Number(row.cost), stock: Number(row.stock), minimum: Number(row.minimum),
    preferredSupplier: row.preferred_supplier || '', trackExpiry: Boolean(row.track_expiry), notes: row.notes || ''
  };
}

function mapApplicationRecord(collection, record) {
  if (collection === 'ingredients') return {
    id: record.id, name: record.name, category: record.category, unit: record.unit,
    cost: record.cost, stock: record.stock, minimum: record.minimum,
    preferred_supplier: record.preferredSupplier || '', track_expiry: record.trackExpiry === true,
    notes: record.notes || ''
  };
  if (collection === 'recipes') return {
    id: record.id, name: record.name, category: record.category,
    menu_price: record.price, wastage: record.wastage,
    batch_yield: record.batchYield, prep_target: record.prepTarget,
    prep_notes: record.prepNotes || '', ingredients: record.ingredients
  };
  if (collection === 'inventoryTransactions') return {
    id: record.id, ingredient_id: record.ingredientId, quantity: record.quantity,
    unit_cost: record.unitCost, transaction_date: dateValue(record.date),
    transaction_type: record.type, note: record.note || '',
    supplier_name: record.supplierName || '', invoice_number: record.invoiceNumber || '',
    invoice_date: record.invoiceDate ? dateValue(record.invoiceDate) : null,
    batch_code: record.batchCode || null,
    expiration_date: record.expirationDate ? dateValue(record.expirationDate) : null
  };
  if (collection === 'productionLogs') return { id: record.id, recipe_id: record.recipeId, quantity: record.quantity, covers_produced: record.coversProduced == null ? null : record.coversProduced, production_date: dateValue(record.date), mode: record.mode };
  if (collection === 'wasteLogs') return {
    id: record.id, ingredient_id: record.ingredientId, quantity: record.quantity,
    reason: record.reason, waste_date: dateValue(record.date),
    production_log_id: record.productionLogId || null,
    recorded_at: record.recordedAt || new Date().toISOString(), notes: record.notes || ''
  };
  if (collection === 'physicalCounts') return { id: record.id, ingredient_id: record.ingredientId, expected: record.expected, actual: record.actual, count_date: dateValue(record.date) };
  if (collection === 'revenueRecords') return {
    id: record.id, business_date: dateValue(record.business_date), meal_period: record.meal_period,
    reservation_id: record.reservation_id || null,
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
    type: record.type || 'Reservation', seated_at: record.seatedAt || null, completed_at: record.completedAt || null,
    actual_covers: record.actualCovers == null ? null : record.actualCovers,
    last_correction_reason: record.correctionReason || ''
  };
  if (collection === 'restaurantTables') return {
    id: record.id, seats: record.seats,
    table_type: record.tableType || 'Unassigned',
    area: record.area || 'Unassigned',
    status: record.status, x: record.x, y: record.y, guest: record.guest || ''
  };
  if (collection === 'buffetRates') return {
    id: record.id, meal_period: record.mealPeriod, day_type: record.dayType,
    adult_rate: record.adultRate, child_rate: record.childRate, senior_pwd_rate: record.seniorPwdRate,
    effective_from: dateValue(record.effectiveFrom), effective_to: record.effectiveTo ? dateValue(record.effectiveTo) : null,
    is_active: record.isActive !== false
  };
  return { id: record.id, name: record.name, category: record.category, unit: record.unit, cost: record.cost, stock: record.stock, minimum: record.minimum };
}

function throwIfError(error) {
  if (error) throw new Error(error.message || 'The database operation failed.');
}

window.supabaseRecord = {
  async loadProductFormOptions() {
    const client = window.supabaseClient;
    const [categories, units, suppliers] = await Promise.all([
      client.from('product_categories').select('name').eq('is_active', true).order('name'),
      client.from('units').select('name,abbreviation').eq('is_active', true).order('name'),
      client.from('suppliers').select('name').eq('is_active', true).order('name')
    ]);
    throwIfError(categories.error);
    throwIfError(units.error);
    throwIfError(suppliers.error);
    return {
      categories: (categories.data || []).map(item => item.name),
      units: units.data || [],
      suppliers: (suppliers.data || []).map(item => item.name)
    };
  },
  async load(collection) {
    const table = tableForCollection[collection];
    if (!table) throw new Error(`Unknown data collection: ${collection}`);
    const client = window.supabaseClient;
    let result;
    if (collection === 'users') {
      result = await client.from('profiles').select('id,email,full_name,role,updated_at').order('full_name');
    } else if (collection === 'ingredients') {
      const { data, error } = await client.rpc('costtrack_load_products');
      throwIfError(error);
      return (data || []).map(row => mapDatabaseRecord(collection, row));
    } else if (collection === 'recipes') {
      const { data, error } = await client.rpc('costtrack_load_recipes');
      throwIfError(error);
      return (data || []).map(row => mapDatabaseRecord(collection, row));
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
    if (collection === 'wasteLogs') {
      const { data, error } = await window.supabaseClient.rpc('costtrack_log_waste', { payload: row });
      throwIfError(error);
      if (data?.updated_at) rememberVersion(collection, record.id, data.updated_at);
      return;
    }
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
    if (collection === 'ingredients') {
      if (version == null && storedVersion) throw new Error('This product changed in another session. Reload the page before saving your change.');
      const { data, error } = await window.supabaseClient.rpc('costtrack_save_product', {
        payload: row,
        expected_updated_at: version || null
      });
      throwIfError(error);
      if (data?.updated_at) rememberVersion(collection, record.id, data.updated_at);
      return;
    }
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
  async createRevenueDraft(reservationId) {
    const { data, error } = await window.supabaseClient.rpc('create_revenue_draft', { reservation_id_value: reservationId });
    throwIfError(error);
    return data;
  },
  async confirmRevenue(revenueId, adjustments) {
    const { data, error } = await window.supabaseClient.rpc('confirm_revenue', {
      revenue_id_value: revenueId,
      adjustments: adjustments || {}
    });
    throwIfError(error);
    return data;
  },
  async reportAnalytics(reportKey, startDate, endDate, groupBy, includeWaste) {
    const { data, error } = await window.supabaseClient.rpc('report_analytics', {
      report_key: reportKey,
      start_date: startDate,
      end_date: endDate,
      group_by: groupBy || 'day',
      include_waste: includeWaste !== false
    });
    throwIfError(error);
    return data || {};
  },
  async receiveDelivery(payload) {
    const { data, error } = await window.supabaseClient.rpc('costtrack_receive_delivery', {
      payload: {
        supplier_name: payload.supplierName,
        invoice_number: payload.invoiceNumber,
        invoice_date: dateValue(payload.invoiceDate),
        received_date: dateValue(payload.receivedDate),
        note: payload.note || '',
        lines: payload.lines.map(line => ({
          id: line.id,
          ingredient_id: line.ingredientId,
          quantity: line.quantity,
          unit_cost: line.unitCost,
          batch_code: line.batchCode || null,
          expiration_date: line.expirationDate ? dateValue(line.expirationDate) : null
        }))
      }
    });
    throwIfError(error);
    return data;
  },
  async getExpectedCovers(serviceDate, mealPeriod) {
    const { data, error } = await window.supabaseClient.rpc('get_expected_covers', {
      service_date: serviceDate,
      meal_period: mealPeriod || null
    });
    throwIfError(error);
    return Array.isArray(data) ? data[0] || {} : data || {};
  },
  async loadProductionBatches(serviceDate) {
    const { data, error } = await window.supabaseClient.rpc('costtrack_load_production_batches', {
      service_date_value: dateValue(serviceDate)
    });
    throwIfError(error);
    return (data || []).map(row => ({
      id: row.id,
      recipeId: row.recipe_id,
      serviceDate: row.service_date,
      batchNumber: Number(row.batch_number),
      batchCount: Number(row.batch_count),
      batchYield: Number(row.batch_yield),
      expectedCovers: Number(row.expected_covers),
      prepTarget: Number(row.prep_target),
      status: row.status,
      startedAt: row.started_at,
      startedBy: row.started_by,
      readyAt: row.ready_at,
      readyBy: row.ready_by,
      productionLogId: row.production_log_id,
      recipeName: row.recipe_name,
      category: row.category
    }));
  },
  async startProductionBatches(recipeId, serviceDate, batchIds) {
    const { data, error } = await window.supabaseClient.rpc('costtrack_start_production_batches', {
      recipe_id_value: recipeId,
      service_date_value: dateValue(serviceDate),
      batch_ids: batchIds
    });
    throwIfError(error);
    return data || [];
  },
  async loadProductionHistory(startDate, endDate) {
    const { data, error } = await window.supabaseClient.rpc('costtrack_load_production_history', {
      start_date_value: dateValue(startDate),
      end_date_value: dateValue(endDate)
    });
    throwIfError(error);
    return (data || []).map(row => ({
      id: row.id,
      recipeId: row.recipe_id,
      serviceDate: row.service_date,
      batchNumber: Number(row.batch_number),
      portions: Number(row.portions),
      status: row.status,
      startedAt: row.started_at,
      readyAt: row.ready_at,
      productionLogId: row.production_log_id,
      recipeName: row.recipe_name,
      category: row.category,
      legacyTimeUnknown: Boolean(row.legacy_time_unknown)
    }));
  },
  async completeProductionBatch(batchId) {
    const { data, error } = await window.supabaseClient.rpc('costtrack_complete_production_batch', {
      batch_id_value: batchId
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
