const assert = require('node:assert/strict');
const test = require('node:test');
const logic = require('./business-logic.js');

const kg = { name: 'Kilogram', abbreviation: 'kg', dimension: 'weight', conversionToBase: 1000 };
const g = { name: 'Gram', abbreviation: 'g', dimension: 'weight', conversionToBase: 1 };
const liter = { name: 'Liter', abbreviation: 'L', dimension: 'volume', conversionToBase: 1000 };
const asOfDate = '2026-11-11';

test('converts compatible units and rejects incompatible dimensions', () => {
  assert.equal(logic.convertQuantity(4000, g, kg), 4);
  assert.throws(() => logic.convertQuantity(1, kg, liter), /dimensions differ/);
});

test('plans FIFO consumption across batches using each batch cost', () => {
  const result = logic.planConsumption({
    batches: [
      { id: 'A', quantityRemaining: 50, unitCost: 120, receivedDate: '2026-11-01' },
      { id: 'B', quantityRemaining: 30, unitCost: 130, receivedDate: '2026-11-05' }
    ],
    quantity: 60,
    recipeUnit: kg,
    stockUnit: kg,
    asOfDate
  });

  assert.equal(result.isSufficient, true);
  assert.deepEqual(result.allocations.map(item => [item.batchId, item.quantity]), [['A', 50], ['B', 10]]);
  assert.equal(result.totalCost, 7300);
  assert.equal(result.shortageQuantity, 0);
});

test('does not consume expired batches and reports an exact shortage', () => {
  const result = logic.planConsumption({
    batches: [
      { id: 'expired', quantityRemaining: 20, unitCost: 5, receivedDate: '2026-10-01', expirationDate: '2026-11-10' },
      { id: 'active', quantityRemaining: 3, unitCost: 8, receivedDate: '2026-11-01' }
    ],
    quantity: 5,
    recipeUnit: kg,
    stockUnit: kg,
    asOfDate
  });

  assert.equal(result.isSufficient, false);
  assert.equal(result.allocatedQuantity, 3);
  assert.equal(result.shortageQuantity, 2);
  assert.deepEqual(result.allocations.map(item => item.batchId), ['active']);
});

test('FIFO uses the older batch first and warns when a newer batch expires sooner', () => {
  const result = logic.planConsumption({
    batches: [
      { id: 'older', quantityRemaining: 100, unitCost: 2, receivedDate: '2026-11-01', expirationDate: '2026-11-20' },
      { id: 'newer', quantityRemaining: 100, unitCost: 3, receivedDate: '2026-11-05', expirationDate: '2026-11-15' }
    ],
    quantity: 20,
    recipeUnit: kg,
    stockUnit: kg,
    asOfDate
  });
  assert.deepEqual(result.allocations.map(item => [item.batchId, item.quantity]), [['older', 20]]);
  assert.equal(result.warnings.length, 1);
});

test('FEFO sorts dated batches before undated batches', () => {
  const ordered = logic.orderBatches([
    { id: 'undated', receivedDate: '2026-11-01' },
    { id: 'later-expiry', receivedDate: '2026-11-01', expirationDate: '2026-12-01' },
    { id: 'sooner-expiry', receivedDate: '2026-11-05', expirationDate: '2026-11-15' }
  ], 'FEFO');
  assert.deepEqual(ordered.map(item => item.id), ['sooner-expiry', 'later-expiry', 'undated']);
});

test('classifies expiring, expired, and depleted stock and totals only available batches', () => {
  assert.equal(logic.batchStatus({ quantityRemaining: 2, expirationDate: '2026-11-13' }, asOfDate, 3).status, 'Expiring soon');
  assert.equal(logic.batchStatus({ quantityRemaining: 2, expirationDate: '2026-11-10' }, asOfDate, 3).status, 'Expired');
  assert.equal(logic.batchStatus({ quantityRemaining: 0 }, asOfDate).status, 'Depleted');
  assert.equal(logic.availableStock([
    { quantityRemaining: 4 },
    { quantityRemaining: 7, expirationDate: '2026-11-10' },
    { quantityRemaining: 3, status: 'Depleted' }
  ], asOfDate), 4);
});

test('computes stock health and batch-weighted average cost', () => {
  assert.equal(logic.stockHealth(0, 10), 'Out of Stock');
  assert.equal(logic.stockHealth(5, 10), 'Low Stock');
  assert.equal(logic.stockHealth(10, 10), 'Healthy');
  assert.equal(logic.weightedAverageUnitCost([
    { quantityRemaining: 50, unitCost: 120 },
    { quantityRemaining: 30, unitCost: 130 }
  ], asOfDate), 123.75);
});

test('tracks buffet prep targets across ready and cooking batches', () => {
  const progress = logic.productionProgress([
    { status: 'Ready', expectedCovers: 30 },
    { status: 'Cooking', batchYield: 30, batchCount: 1 },
    { status: 'Cancelled', expectedCovers: 50 }
  ], 100);
  assert.deepEqual(progress, {
    target: 100,
    ready: 30,
    cooking: 30,
    remaining: 40,
    remainingAfterCooking: 70
  });
  assert.throws(() => logic.productionProgress([], -1), /cannot be negative/);
});

test('enforces role actions and validates signed ledger movements', () => {
  assert.equal(logic.canPerformInventoryAction('Inventory Clerk', 'inventory.receive'), true);
  assert.equal(logic.canPerformInventoryAction('Inventory Clerk', 'product.manage'), false);
  assert.equal(logic.canPerformInventoryAction('Manager', 'product.manage'), false);
  assert.equal(logic.canPerformInventoryAction('Manager', 'inventory.receive'), true);
  assert.equal(logic.canPerformInventoryAction('Chef / Kitchen Staff', 'rates.manage'), false);
  assert.equal(logic.canPerformInventoryAction('Chef / Kitchen Staff', 'revenue.read'), false);
  assert.throws(() => logic.assertInventoryRole('Chef / Kitchen Staff', 'revenue.read'), { code: 'FORBIDDEN' });
  assert.throws(() => logic.createStockMovement({
    type: 'Production', quantity: 2, unitCost: 10, productId: 'p', batchId: 'b', referenceType: 'production', referenceId: '1'
  }), /negative quantity/);
  assert.equal(logic.createStockMovement({
    type: 'Production', quantity: -2, unitCost: 10, productId: 'p', batchId: 'b', referenceType: 'production', referenceId: '1'
  }).cost, 20);
});
