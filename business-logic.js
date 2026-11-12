(function exposeCostTrackLogic(root) {
  const INVENTORY_ACTION_ROLES = {
    'product.read': ['Administrator', 'Manager', 'Inventory Clerk', 'Chef / Kitchen Staff'],
    'product.manage': ['Administrator'],
    'inventory.read': ['Administrator', 'Manager', 'Inventory Clerk', 'Chef / Kitchen Staff'],
    'inventory.receive': ['Administrator', 'Manager', 'Inventory Clerk'],
    'inventory.adjust': ['Administrator', 'Manager'],
    'recipe.read': ['Administrator', 'Manager', 'Chef / Kitchen Staff'],
    'recipe.manage': ['Administrator', 'Manager'],
    'production.log': ['Administrator', 'Manager', 'Chef / Kitchen Staff'],
    'production.override': ['Administrator', 'Manager'],
    'waste.log': ['Administrator', 'Manager', 'Chef / Kitchen Staff'],
    'count.submit': ['Administrator', 'Inventory Clerk'],
    'count.approve': ['Administrator', 'Manager'],
    'revenue.read': ['Administrator', 'Manager'],
    'rates.manage': ['Administrator', 'Manager'],
    'supplier.manage': ['Administrator', 'Manager'],
    'user.manage': ['Administrator'],
    'settings.manage': ['Administrator']
  };
  const MOVEMENT_SIGNS = {
    'Opening balance': 1,
    Received: 1,
    Production: -1,
    Waste: -1,
    'Expired write-off': -1,
    'Count adjustment': 0,
    'Void reversal': 0
  };

  function number(value, label) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) throw new TypeError(`${label} must be a finite number.`);
    return parsed;
  }

  function quantity4(value) {
    return Number(number(value, 'Quantity').toFixed(4));
  }

  function parseDate(value, label) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      throw new TypeError(`${label} must be a date in YYYY-MM-DD format.`);
    }
    const date = new Date(`${value}T00:00:00.000Z`);
    if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
      throw new TypeError(`${label} must be a valid calendar date.`);
    }
    return date;
  }

  function unitFactor(unit) {
    const dimension = unit?.dimension;
    const factor = number(unit?.conversionToBase ?? unit?.conversion_to_base, 'Unit conversion factor');
    if (!dimension || dimension === 'unknown' || factor <= 0) {
      throw new RangeError('This unit has no verified conversion. Ask an administrator to configure it.');
    }
    return { dimension, factor };
  }

  function convertQuantity(value, fromUnit, toUnit) {
    const quantity = number(value, 'Quantity');
    if (quantity < 0) throw new RangeError('Quantity cannot be negative.');
    const from = unitFactor(fromUnit);
    const to = unitFactor(toUnit);
    if (from.dimension !== to.dimension) {
      throw new RangeError(`Cannot convert ${fromUnit.abbreviation || fromUnit.name} to ${toUnit.abbreviation || toUnit.name}: their dimensions differ.`);
    }
    return quantity4(quantity * from.factor / to.factor);
  }

  function daysBetween(from, to) {
    return Math.round((parseDate(to, 'Comparison date') - parseDate(from, 'Expiration date')) / 86400000);
  }

  function batchStatus(batch, asOfDate, alertDays = 3) {
    const remaining = number(batch.quantityRemaining ?? batch.quantity_remaining ?? 0, 'Remaining quantity');
    const storedStatus = String(batch.status || 'Active').toLowerCase();
    if (storedStatus === 'voided') return { status: 'Voided', daysUntilExpiry: null };
    if (remaining <= 0 || storedStatus === 'depleted') return { status: 'Depleted', daysUntilExpiry: null };
    const expirationDate = batch.expirationDate ?? batch.expiration_date;
    if (!expirationDate) return { status: 'Active', daysUntilExpiry: null };
    const daysUntilExpiry = daysBetween(asOfDate, expirationDate);
    if (daysUntilExpiry < 0 || storedStatus === 'expired') return { status: 'Expired', daysUntilExpiry };
    const days = number(alertDays, 'Expiry alert days');
    return {
      status: daysUntilExpiry <= days ? 'Expiring soon' : 'Active',
      daysUntilExpiry
    };
  }

  function availableStock(batches, asOfDate) {
    return quantity4(batches.reduce((total, batch) => {
      const { status } = batchStatus(batch, asOfDate, -1);
      if (status !== 'Active') return total;
      return total + number(batch.quantityRemaining ?? batch.quantity_remaining ?? 0, 'Remaining quantity');
    }, 0));
  }

  function stockHealth(quantity, threshold) {
    const stock = number(quantity, 'Stock quantity');
    const minimum = number(threshold, 'Stock threshold');
    if (stock < 0 || minimum < 0) throw new RangeError('Stock and threshold cannot be negative.');
    if (stock === 0) return 'Out of Stock';
    return stock < minimum ? 'Low Stock' : 'Healthy';
  }

  function orderBatches(batches, method) {
    if (!['FIFO', 'FEFO'].includes(method)) throw new RangeError('Consumption method must be FIFO or FEFO.');
    return batches.slice().sort((left, right) => {
      if (method === 'FEFO') {
        const leftExpiry = left.expirationDate ?? left.expiration_date ?? '9999-12-31';
        const rightExpiry = right.expirationDate ?? right.expiration_date ?? '9999-12-31';
        const byExpiry = leftExpiry.localeCompare(rightExpiry);
        if (byExpiry) return byExpiry;
      }
      const leftReceived = left.receivedDate ?? left.received_date ?? '';
      const rightReceived = right.receivedDate ?? right.received_date ?? '';
      return leftReceived.localeCompare(rightReceived) || String(left.id).localeCompare(String(right.id));
    });
  }

  function planConsumption({ batches, quantity, recipeUnit, stockUnit, method = 'FIFO', asOfDate }) {
    if (!Array.isArray(batches) || !recipeUnit || !stockUnit || !asOfDate) {
      throw new TypeError('Batches, recipeUnit, stockUnit, and asOfDate are required.');
    }
    const requested = convertQuantity(quantity, recipeUnit, stockUnit);
    const eligible = batches.filter(batch => {
      const status = batchStatus(batch, asOfDate, -1).status;
      return status === 'Active'
        && number(batch.quantityRemaining ?? batch.quantity_remaining ?? 0, 'Remaining quantity') > 0;
    });
    const ordered = orderBatches(eligible, method);
    const warnings = [];
    if (method === 'FIFO') {
      const dated = orderBatches(eligible, 'FIFO').filter(batch => batch.expirationDate || batch.expiration_date);
      for (let olderIndex = 0; olderIndex < dated.length && !warnings.length; olderIndex += 1) {
        const olderExpiry = dated[olderIndex].expirationDate ?? dated[olderIndex].expiration_date;
        for (let newerIndex = olderIndex + 1; newerIndex < dated.length; newerIndex += 1) {
          const newerExpiry = dated[newerIndex].expirationDate ?? dated[newerIndex].expiration_date;
          if (newerExpiry < olderExpiry) {
            warnings.push('A newer batch expires sooner than an older batch.');
            break;
          }
        }
      }
    }

    let remaining = requested;
    const allocations = [];
    for (const batch of ordered) {
      if (remaining <= 0) break;
      const batchQuantity = number(batch.quantityRemaining ?? batch.quantity_remaining, 'Remaining quantity');
      const quantityUsed = quantity4(Math.min(batchQuantity, remaining));
      const unitCost = number(batch.unitCost ?? batch.unit_cost ?? 0, 'Batch unit cost');
      if (unitCost < 0) throw new RangeError('Batch unit cost cannot be negative.');
      allocations.push({
        batchId: batch.id,
        quantity: quantityUsed,
        unitCost,
        cost: quantityUsed * unitCost
      });
      remaining = quantity4(remaining - quantityUsed);
    }
    const allocated = quantity4(requested - remaining);
    return {
      method,
      requestedQuantity: requested,
      allocatedQuantity: allocated,
      shortageQuantity: remaining,
      isSufficient: remaining === 0,
      allocations,
      totalCost: allocations.reduce((total, allocation) => total + allocation.cost, 0),
      warnings
    };
  }

  function weightedAverageUnitCost(batches, asOfDate) {
    const active = batches.filter(batch => batchStatus(batch, asOfDate, -1).status === 'Active');
    const quantity = active.reduce((sum, batch) => sum + number(batch.quantityRemaining ?? batch.quantity_remaining, 'Remaining quantity'), 0);
    if (!quantity) return null;
    return active.reduce((sum, batch) => (
      sum + number(batch.quantityRemaining ?? batch.quantity_remaining, 'Remaining quantity')
        * number(batch.unitCost ?? batch.unit_cost ?? 0, 'Batch unit cost')
    ), 0) / quantity;
  }

  function productionProgress(batches, prepTarget) {
    if (!Array.isArray(batches)) throw new TypeError('Production batches must be an array.');
    const target = number(prepTarget, 'Prep target');
    if (target < 0) throw new RangeError('Prep target cannot be negative.');
    const portions = batch => {
      const expected = batch.expectedCovers ?? batch.expected_covers;
      if (expected != null) return number(expected, 'Expected portions');
      const batchYield = number(batch.batchYield ?? batch.batch_yield ?? 0, 'Batch yield');
      const batchCount = number(batch.batchCount ?? batch.batch_count ?? 1, 'Batch count');
      return batchYield * batchCount;
    };
    const ready = batches.filter(batch => batch.status === 'Ready').reduce((sum, batch) => sum + portions(batch), 0);
    const cooking = batches.filter(batch => batch.status === 'Cooking').reduce((sum, batch) => sum + portions(batch), 0);
    return {
      target,
      ready,
      cooking,
      remaining: Math.max(0, target - ready - cooking),
      remainingAfterCooking: Math.max(0, target - ready)
    };
  }

  function createStockMovement(movement) {
    if (!movement || !Object.hasOwn(MOVEMENT_SIGNS, movement.type)) {
      throw new TypeError('A supported stock movement type is required.');
    }
    const quantity = number(movement.quantity, 'Movement quantity');
    if (quantity === 0) throw new RangeError('Movement quantity cannot be zero.');
    const expectedSign = MOVEMENT_SIGNS[movement.type];
    if (expectedSign && Math.sign(quantity) !== expectedSign) {
      throw new RangeError(`${movement.type} movements must have a ${expectedSign > 0 ? 'positive' : 'negative'} quantity.`);
    }
    if (!movement.productId || !movement.batchId || !movement.referenceType || !movement.referenceId) {
      throw new TypeError('Product, batch, and source reference are required for a stock movement.');
    }
    const unitCost = number(movement.unitCost, 'Unit cost');
    if (unitCost < 0) throw new RangeError('Unit cost cannot be negative.');
    return {
      ...movement,
      quantity: quantity4(quantity),
      unitCost,
      cost: Math.abs(quantity) * unitCost,
      createdAt: movement.createdAt || new Date().toISOString()
    };
  }

  function canPerformInventoryAction(role, action) {
    return Boolean(INVENTORY_ACTION_ROLES[action]?.includes(role));
  }

  function assertInventoryRole(role, action) {
    if (!canPerformInventoryAction(role, action)) {
      const error = new Error(`Not authorized to perform ${action}.`);
      error.code = 'FORBIDDEN';
      throw error;
    }
  }

  function createRevenueRecord(data) {
    const adultCustomers = Number(data.adult_customers || 0);
    const childCustomers = Number(data.child_customers || 0);
    const seniorCustomers = Number(data.senior_pwd_customers || 0);
    const adultRate = Number(data.adult_rate);
    const childRate = Number(data.child_rate);
    const seniorRate = Number(data.senior_pwd_rate);
    const counts = [adultCustomers, childCustomers, seniorCustomers];
    const rates = [adultRate, childRate, seniorRate];
    if (counts.some(value => !Number.isInteger(value) || value < 0)) throw new RangeError('Customer counts must be non-negative whole numbers.');
    if (counts.reduce((sum, value) => sum + value, 0) < 1) throw new RangeError('At least one customer is required.');
    if (rates.some(value => !Number.isFinite(value) || value < 0)) throw new RangeError('Revenue rates must be valid non-negative amounts.');
    return {
      status: data.status || 'Confirmed',
      ...data,
      adult_customers: adultCustomers,
      adult_rate: adultRate,
      child_customers: childCustomers,
      child_rate: childRate,
      senior_pwd_customers: seniorCustomers,
      senior_pwd_rate: seniorRate,
      adult_revenue: adultCustomers * adultRate,
      child_revenue: childCustomers * childRate,
      senior_pwd_revenue: seniorCustomers * seniorRate,
      total_customers: adultCustomers + childCustomers + seniorCustomers,
      total_revenue: adultCustomers * adultRate + childCustomers * childRate + seniorCustomers * seniorRate
    };
  }

  function computedRecipeCost(recipe, ingredients) {
    const ingredientById = new Map(ingredients.map(item => [item.id, item]));
    const wastage = Number(recipe.wastage || 0);
    if (!Number.isFinite(wastage) || wastage < 0) throw new RangeError('Recipe wastage must be a non-negative number.');
    const baseCost = recipe.ingredients.reduce((sum, line) => {
      const item = ingredientById.get(line.ingredientId);
      const quantity = Number(line.quantity);
      if (!item || !Number.isFinite(quantity) || quantity <= 0) throw new RangeError('Recipe ingredients must reference valid inventory with positive quantities.');
      return sum + Number(item.cost) * quantity;
    }, 0);
    return baseCost * (1 + wastage / 100);
  }

  function reservationRevenue(reservation, rates = {}) {
    const covers = reservation.actualCovers ?? reservation.guests ?? (Number(reservation.adults || 0) + Number(reservation.children || 0));
    const adults = Number(reservation.adults || covers || 0);
    const children = Number(reservation.children || 0);
    if (!Number.isInteger(covers) || covers < 0 || ![adults, children].every(value => Number.isInteger(value) && value >= 0)) {
      throw new RangeError('Reservation guest counts must be non-negative whole numbers.');
    }
    const adultRate = Number(rates.adult_rate ?? rates.adultRate);
    const childRate = Number(rates.child_rate ?? rates.childRate);
    if (![adultRate, childRate].every(value => Number.isFinite(value) && value >= 0)) {
      throw new RangeError('No active buffet rate exists for this reservation.');
    }
    return covers === adults + children ? adults * adultRate + children * childRate : covers * adultRate;
  }

  const logic = {
    assertInventoryRole,
    availableStock,
    batchStatus,
    canPerformInventoryAction,
    convertQuantity,
    createRevenueRecord,
    createStockMovement,
    computedRecipeCost,
    orderBatches,
    planConsumption,
    productionProgress,
    reservationRevenue,
    stockHealth,
    weightedAverageUnitCost
  };
  root.CostTrackLogic = logic;
  if (typeof module !== 'undefined' && module.exports) module.exports = logic;
})(globalThis);
