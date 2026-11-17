const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const configSource = fs.readFileSync(path.join(__dirname, 'supabase-config.js'), 'utf8');

function loadSupabaseRecord(rpc, clientOverrides = {}) {
  const timers = new Map();
  let nextTimerId = 0;
  const mockWindow = {
    setTimeout(callback, delay) {
      assert.equal(delay, 15000);
      const id = ++nextTimerId;
      timers.set(id, callback);
      return id;
    },
    clearTimeout(id) {
      timers.delete(id);
    },
    supabase: {
      createClient() {
        return { rpc, ...clientOverrides };
      }
    }
  };
  vm.runInNewContext(configSource, { window: mockWindow, AbortController });
  return { record: mockWindow.supabaseRecord, timers };
}

test('posSaveBill aborts and rejects a pending RPC after 15 seconds', async () => {
  let signal;
  const { record, timers } = loadSupabaseRecord(() => ({
    abortSignal(requestSignal) {
      signal = requestSignal;
      return new Promise(() => {});
    }
  }));
  const pending = record.posSaveBill({
    adultCount: 1,
    seniorCount: 0,
    kidsCount: 0,
    compedCount: 0,
    idempotencyKey: 'same-request'
  });
  const [timeout] = timers.values();

  timeout();

  await assert.rejects(
    pending,
    /Bill save timed out after 15 seconds\..*same form.*idempotency key/
  );
  assert.equal(signal.aborted, true);
  assert.equal(timers.size, 0);
});

test('reservation mapping preserves Senior/PWD count and source in both directions', async () => {
  let inserted;
  const client = {
    from(table) {
      assert.equal(table, 'reservations');
      return {
        insert(row) {
          inserted = row;
          return {
            select() {
              return {
                async single() {
                  return { data: { updated_at: '2026-11-11T00:00:00Z' }, error: null };
                }
              };
            }
          };
        }
      };
    }
  };
  const { record } = loadSupabaseRecord(() => ({}), client);
  const mapped = record.mapRecord('reservations', {
    id: 'RS-1',
    name: 'Guest',
    reservation_date: '2026-11-11',
    reservation_time: '11:00 AM',
    guests: 7,
    adults: 4,
    senior_pwd_count: 1,
    children: 2,
    source: 'Phone',
    status: 'Pending',
    type: 'Reservation',
    package_override_reason: 'Approved event exception'
  });

  assert.equal(mapped.seniorPwdCount, 1);
  assert.equal(mapped.source, 'Phone');
  assert.equal(mapped.packageOverrideReason, 'Approved event exception');
  await record.upsert('reservations', {
    id: 'RS-1',
    date: '2026-11-11',
    time: '11:00 AM',
    guests: 7,
    adults: 4,
    seniorPwdCount: 1,
    children: 2,
    source: 'Phone',
    status: 'Pending',
    type: 'Reservation',
    packageOverrideReason: 'Approved event exception'
  });
  assert.equal(inserted.senior_pwd_count, 1);
  assert.equal(inserted.source, 'Phone');
  assert.equal(inserted.package_override_reason, 'Approved event exception');
});

test('posSaveBill returns a successful RPC response without waiting for its timeout', async () => {
  const expected = { bill: { id: 'bill-1' } };
  const { record, timers } = loadSupabaseRecord(() => ({
    abortSignal() {
      return Promise.resolve({ data: expected, error: null });
    }
  }));

  assert.equal(await record.posSaveBill({}), expected);
  assert.equal(timers.size, 0);
});

test('posCloseBill sends the bill, tender, and idempotency key and clears its timeout', async () => {
  let call;
  const expected = { bill: { id: 'bill-1', status: 'Closed' } };
  const { record, timers } = loadSupabaseRecord((name, args) => {
    call = { name, args };
    return {
      abortSignal() {
        return Promise.resolve({ data: expected, error: null });
      }
    };
  });

  assert.equal(await record.posCloseBill('bill-1', 1496, 'same-payment-key'), expected);
  assert.equal(call.name, 'pos_close_bill_phase3');
  assert.equal(call.args.p_bill_id, 'bill-1');
  assert.equal(call.args.p_tendered_amount, 1496);
  assert.equal(call.args.p_idempotency_key, 'same-payment-key');
  assert.equal(timers.size, 0);
});

test('posCloseBill aborts and reports when the RPC does not respond within 15 seconds', async () => {
  let signal;
  const { record, timers } = loadSupabaseRecord(() => ({
    abortSignal(requestSignal) {
      signal = requestSignal;
      return new Promise(() => {});
    }
  }));
  const pending = record.posCloseBill('bill-1', 1496, 'retry-same-payment');
  const [timeout] = timers.values();

  timeout();

  await assert.rejects(
    pending,
    /Bill close timed out after 15 seconds\..*same payment form.*idempotency key/
  );
  assert.equal(signal.aborted, true);
  assert.equal(timers.size, 0);
});

test('posListUnresolvedStaleBookings calls the role-guarded listing RPC', async () => {
  let call;
  const expected = [{ reservation_id: 'reservation-1', resolution_label: 'Payable' }];
  const { record, timers } = loadSupabaseRecord(name => {
    call = { name };
    return {
      abortSignal() {
        return Promise.resolve({ data: expected, error: null });
      }
    };
  });

  assert.deepEqual(await record.posListUnresolvedStaleBookings(), expected);
  assert.equal(call.name, 'pos_list_unresolved_stale_bookings');
  assert.equal(timers.size, 0);
});

test('posResolveStaleBooking sends explicit outcome, confirmation, deposit, and idempotency arguments', async () => {
  let call;
  const expected = { reservation_id: 'reservation-1', status: 'Completed' };
  const { record, timers } = loadSupabaseRecord((name, args) => {
    call = { name, args };
    return {
      abortSignal() {
        return Promise.resolve({ data: expected, error: null });
      }
    };
  });

  assert.equal(await record.posResolveStaleBooking({
    reservationId: 'reservation-1',
    outcome: 'close_without_charge',
    reason: 'Verified test record; no meal was served.',
    confirmNoMeal: true,
    depositAction: 'refund',
    depositReason: 'Return the held customer deposit.',
    idempotencyKey: 'same-resolution-key'
  }), expected);
  assert.equal(call.name, 'pos_resolve_stale_booking');
  assert.equal(JSON.stringify(call.args), JSON.stringify({
    p_reservation_id: 'reservation-1',
    p_outcome: 'close_without_charge',
    p_reason: 'Verified test record; no meal was served.',
    p_confirm_no_meal: true,
    p_deposit_action: 'refund',
    p_deposit_reason: 'Return the held customer deposit.',
    p_idempotency_key: 'same-resolution-key'
  }));
  assert.equal(timers.size, 0);
});

test('posResolveStaleBooking aborts after 15 seconds and retains retry guidance', async () => {
  let signal;
  const { record, timers } = loadSupabaseRecord(() => ({
    abortSignal(requestSignal) {
      signal = requestSignal;
      return new Promise(() => {});
    }
  }));
  const pending = record.posResolveStaleBooking({
    reservationId: 'reservation-1',
    outcome: 'close_without_charge',
    reason: 'Verified test record; no meal was served.',
    confirmNoMeal: true,
    idempotencyKey: 'retry-same-resolution'
  });
  const [timeout] = timers.values();

  timeout();

  await assert.rejects(
    pending,
    /Stale booking resolution timed out after 15 seconds\..*same dialog.*idempotency key/
  );
  assert.equal(signal.aborted, true);
  assert.equal(timers.size, 0);
});

test('posListUnresolvedStaleBookings reports a timeout and aborts the request', async () => {
  let signal;
  const { record, timers } = loadSupabaseRecord(() => ({
    abortSignal(requestSignal) {
      signal = requestSignal;
      return new Promise(() => {});
    }
  }));
  const pending = record.posListUnresolvedStaleBookings();
  const [timeout] = timers.values();

  timeout();

  await assert.rejects(pending, /Unresolved bookings request timed out after 15 seconds/);
  assert.equal(signal.aborted, true);
  assert.equal(timers.size, 0);
});

test('posSeatAndOpenWalkIn sends all counts and the stable idempotency key', async () => {
  let call;
  const expected = { reservation: { id: 'walk-in-1' }, bill: { id: 'bill-1' } };
  const { record, timers } = loadSupabaseRecord((name, args) => {
    call = { name, args };
    return {
      abortSignal() {
        return Promise.resolve({ data: expected, error: null });
      }
    };
  });

  assert.equal(await record.posSeatAndOpenWalkIn({
    customerName: 'Walk-in guest',
    phone: '',
    email: '',
    date: '2026-11-11',
    time: '12:00 PM',
    tableId: 'T05',
    adultCount: 4,
    seniorCount: 1,
    kidsCount: 2,
    notes: '',
    idempotencyKey: 'same-walk-in-request'
  }), expected);
  assert.equal(call.name, 'pos_seat_and_open_walkin');
  assert.equal(call.args.p_adult_count, 4);
  assert.equal(call.args.p_senior_count, 1);
  assert.equal(call.args.p_kids_count, 2);
  assert.equal(call.args.p_idempotency_key, 'same-walk-in-request');
  assert.equal(timers.size, 0);
});

test('posSeatAndOpenWalkIn aborts after the 15-second timeout', async () => {
  let signal;
  const { record, timers } = loadSupabaseRecord(() => ({
    abortSignal(requestSignal) {
      signal = requestSignal;
      return new Promise(() => {});
    }
  }));
  const pending = record.posSeatAndOpenWalkIn({
    idempotencyKey: 'retry-same-request'
  });
  const [timeout] = timers.values();

  timeout();

  await assert.rejects(pending, /Walk-in seat-and-bill request timed out after 15 seconds\..*same form.*idempotency key/);
  assert.equal(signal.aborted, true);
  assert.equal(timers.size, 0);
});
