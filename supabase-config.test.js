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
    type: 'Reservation'
  });

  assert.equal(mapped.seniorPwdCount, 1);
  assert.equal(mapped.source, 'Phone');
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
    type: 'Reservation'
  });
  assert.equal(inserted.senior_pwd_count, 1);
  assert.equal(inserted.source, 'Phone');
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
