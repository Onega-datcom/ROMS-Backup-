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

test('limits two-hour reservation windows to restaurant hours and generates half-hour slots', () => {
  assert.equal(logic.isReservationTimeWithinOpenHours('10:00 AM'), true);
  assert.equal(logic.isReservationTimeWithinOpenHours('7:00 PM'), true);
  assert.equal(logic.isReservationTimeWithinOpenHours('07:00 PM'), true);
  assert.equal(logic.isReservationTimeWithinOpenHours('7:30 PM'), false);
  assert.equal(logic.isReservationTimeWithinOpenHours('8:30PM'), false);
  assert.equal(logic.isReservationTimeWithinOpenHours('9:00 PM'), false);
  assert.equal(logic.isReservationTimeWithinOpenHours('9:30 AM'), false);
  assert.equal(logic.isReservationTimeWithinOpenHours('invalid'), false);
  assert.equal(logic.reservationTimeSlots()[0], '10:00 AM');
  const slots = logic.reservationTimeSlots();
  assert.equal(slots[slots.length - 1], '7:00 PM');
  assert.equal(slots.length, 19);
  assert.equal(logic.reservationEndTime('7:00 PM'), '9:00 PM');
});

test('preserves generated reservation IDs despite the form hidden ID and retains existing booking type', () => {
  const first = logic.buildReservationRecord(
    null,
    { id: '', name: 'Customer One', type: '' },
    'RS-FIRST'
  );
  const second = logic.buildReservationRecord(
    null,
    { id: '', name: 'Customer Two', type: '' },
    'RS-SECOND'
  );
  const edited = logic.buildReservationRecord(
    { id: 'RS-FIRST', type: 'Walk-in', name: 'Original' },
    { id: 'RS-FIRST', type: 'Reservation', name: 'Updated' },
    'RS-UNUSED'
  );

  assert.equal(first.id, 'RS-FIRST');
  assert.equal(second.id, 'RS-SECOND');
  assert.notEqual(first.id, second.id);
  assert.equal(edited.id, 'RS-FIRST');
  assert.equal(edited.type, 'Walk-in');
});

test('derives live table availability from bookings and checks overlapping two-hour windows', () => {
  const table = { id: 'T1', status: 'Available' };
  const bookings = [
    { id: 'r2', table: 'T1', date: '2026-11-12', time: '6:00 PM', status: 'Confirmed' },
    { id: 'r1', table: 'T1', date: '2026-11-12', time: '11:00 AM', status: 'Pending' },
    { id: 'no-show', table: 'T1', date: '2026-11-12', time: '3:00 PM', status: 'No-show' },
    { id: 'old', table: 'T1', date: '2026-11-12', time: '1:00 PM', status: 'Cancelled' }
  ];

  const availability = logic.tableAvailability(table, bookings, '2026-11-12', '2026-11-12');
  assert.equal(availability.status, 'Reserved');
  assert.equal(availability.primaryBooking.id, 'r1');
  assert.equal(logic.tableHasReservationConflict('T1', '2026-11-12', '6:00 PM', bookings), true);
  assert.equal(logic.tableHasReservationConflict('T1', '2026-11-12', '6:00 PM', bookings, 'r2'), false);
  assert.equal(logic.tableHasReservationConflict('T1', '2026-11-12', '12:30 PM', bookings), true);
  assert.equal(logic.tableHasReservationConflict('T1', '2026-11-12', '1:00 PM', bookings), false);
  assert.equal(logic.tableHasReservationConflict('T1', '2026-11-12', '3:00 PM', bookings), false);
  assert.equal(logic.reservationTimeOverlaps('1:00 PM', '2:30 PM'), true);
  assert.equal(logic.reservationTimeOverlaps('1:00 PM', '3:00 PM'), false);
  const sameDayBookings = [
    { id: 'first', table: 'T07', date: '2026-11-13', time: '1:00 PM', status: 'Pending' },
    { id: 'second', table: 'T15', date: '2026-11-13', time: '3:00 PM', status: 'Pending' }
  ];
  assert.equal(logic.tableHasReservationConflict('T07', '2026-11-13', '3:00 PM', sameDayBookings), false);
  assert.equal(logic.tableHasReservationConflict('T15', '2026-11-13', '1:00 PM', sameDayBookings), false);
  assert.equal(logic.tableHasReservationConflict('T07', '2026-11-13', '1:00 PM', sameDayBookings), true);

  const occupied = logic.tableAvailability(
    table,
    [...bookings, { id: 'r3', table: 'T1', date: '2026-11-12', time: '2:00 PM', status: 'Seated' }],
    '2026-11-12',
    '2026-11-12'
  );
  assert.equal(occupied.status, 'Occupied');
  assert.equal(occupied.primaryBooking.id, 'r3');

  const staleOccupied = logic.tableAvailability(
    { id: 'T2', status: 'Occupied', guest: 'Old cached guest' },
    [],
    '2026-11-12',
    '2026-11-12'
  );
  assert.equal(staleOccupied.status, 'Available');
  assert.equal(staleOccupied.primaryBooking, null);
});

test('keeps an overdue seated table occupied and marks it for staff attention', () => {
  const now = new Date(2026, 10, 13, 15, 0);
  const seated = {
    id: 'walk-in-1',
    table: 'T1',
    date: '2026-11-13',
    time: '1:00 PM',
    seatedAt: '2026-11-13T13:15:00Z',
    status: 'Seated'
  };
  const availability = logic.tableAvailability(
    { id: 'T1', status: 'Available' },
    [seated],
    '2026-11-13',
    '2026-11-13',
    15 * 60,
    now
  );
  assert.equal(availability.status, 'Occupied');
  assert.equal(availability.stayLimitReached, true);
  assert.equal(logic.reservationStayLimitReached(seated, new Date(2026, 10, 13, 14, 59)), false);
});

test('keeps an unresolved prior-day seating occupied and blocks a new assignment today', () => {
  const priorDaySeating = {
    id: 'walk-in-previous-day',
    table: 'T1',
    date: '2026-11-12',
    time: '8:00 PM',
    status: 'Seated'
  };
  const availability = logic.tableAvailability(
    { id: 'T1', status: 'Available' },
    [priorDaySeating],
    '2026-11-13',
    '2026-11-13',
    10 * 60,
    new Date(2026, 10, 13, 10, 0)
  );
  assert.equal(availability.status, 'Occupied');
  assert.equal(availability.primaryBooking.id, 'walk-in-previous-day');
  assert.equal(
    logic.tableHasReservationConflict('T1', '2026-11-13', '10:00 AM', [priorDaySeating], '', '2026-11-13'),
    true
  );
});

test('flags unclosed bookings whose two-hour window has passed', () => {
  const booking = {
    id: 'reservation-1',
    table: 'T1',
    date: '2026-11-13',
    time: '10:00 AM',
    status: 'Confirmed'
  };
  const availability = logic.tableAvailability(
    { id: 'T1' },
    [booking],
    '2026-11-13',
    '2026-11-13',
    12 * 60
  );
  assert.equal(availability.status, 'Reserved');
  assert.equal(availability.bookingWindowEnded, true);
});

test('reconciles existing tables to the requested layout while preserving IDs and reservation details', () => {
  const emptyPlan = logic.planRestaurantTableLayout([]);
  assert.equal(emptyPlan.expectedTableCount, 15);
  assert.equal(emptyPlan.additions.length, 15);
  assert.equal(emptyPlan.additions.filter(table => table.tableType === 'Family').length, 3);
  assert.equal(emptyPlan.additions.filter(table => table.tableType === 'Casual' && table.area === 'Front').length, 6);
  assert.equal(emptyPlan.additions.filter(table => table.tableType === 'Casual' && table.area === 'Back').length, 6);
  assert.deepEqual(
    emptyPlan.additions.reduce((counts, table) => {
      counts[table.seats] = (counts[table.seats] || 0) + 1;
      return counts;
    }, {}),
    { 2: 1, 4: 4, 5: 3, 6: 3, 8: 2, 12: 2 }
  );

  const existing = [
    { id: 'T08', seats: 4, status: 'Reserved', tableType: 'Unassigned', area: 'Unassigned', guest: 'Guest A' },
    { id: 'T09', seats: 8, status: 'Available', tableType: 'Unassigned', area: 'Unassigned', guest: '' },
    { id: 'T10', seats: 12, status: 'Occupied', tableType: 'Unassigned', area: 'Unassigned', guest: 'Guest B' }
  ];
  const plan = logic.planRestaurantTableLayout(existing, [], '2026-11-12');
  assert.equal(plan.updates.length, 3);
  assert.equal(plan.additions.length, 12);
  assert.deepEqual(plan.updates.map(table => [table.id, table.seats]), [['T08', 12], ['T09', 12], ['T10', 8]]);
  for (const original of existing) {
    const updated = plan.updates.find(table => table.id === original.id);
    assert.ok(updated);
    assert.equal(updated.status, original.status);
    assert.equal(updated.guest, original.guest);
  }

  const finalTables = [...plan.updates, ...plan.additions];
  assert.equal(finalTables.length, 15);
  assert.equal(finalTables.reduce((sum, table) => sum + table.seats, 0), 91);
  assert.deepEqual(
    finalTables.reduce((counts, table) => {
      counts[table.seats] = (counts[table.seats] || 0) + 1;
      return counts;
    }, {}),
    { 2: 1, 4: 4, 5: 3, 6: 3, 8: 2, 12: 2 }
  );
});

test('blocks a capacity reduction that would make an upcoming active reservation too large', () => {
  const plan = logic.planRestaurantTableLayout(
    [
      { id: 'T01', seats: 12 },
      { id: 'T02', seats: 12 },
      { id: 'T03', seats: 12, status: 'Reserved' }
    ],
    [
      { id: 'active', table: 'T03', date: '2026-11-13', status: 'Confirmed', guests: 10 },
      { id: 'past', table: 'T03', date: '2026-11-10', status: 'Completed', guests: 12 },
      { id: 'cancelled', table: 'T03', date: '2026-11-14', status: 'Cancelled', guests: 12 }
    ],
    '2026-11-12'
  );
  assert.deepEqual(plan.conflicts, [{ tableId: 'T03', targetSeats: 8, reservationIds: ['active'] }]);
});

test('preserves extra legacy tables and marks them unclassified', () => {
  const plan = logic.planRestaurantTableLayout([
    ...Array.from({ length: 15 }, (_, index) => ({ id: `T${String(index + 1).padStart(2, '0')}`, seats: 2 })),
    { id: 'T16', seats: 6, tableType: 'Casual', area: 'Front', status: 'Available' }
  ], [], '2026-11-12');
  assert.equal(plan.additions.length, 0);
  assert.equal(plan.unmatchedTables.length, 1);
  assert.deepEqual(plan.updates.find(table => table.id === 'T16'), {
    id: 'T16', seats: 6, tableType: 'Unassigned', area: 'Unassigned', status: 'Available'
  });
});
